import 'package:reproot/core/api/api_client.dart';
import 'package:reproot/core/api/chat_api.dart';
import 'package:reproot/core/api/forms_groups_api.dart';
import 'package:reproot/core/api/references_api.dart';
import 'package:reproot/core/api/templates_api.dart';
import 'package:reproot/core/api/professional_auth_api.dart';
import 'package:reproot/core/session/session_store.dart';
import 'package:reproot/shared/charts/analytics_types.dart';
import 'package:reproot/shared/charts/graph_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live read-only smoke test for the four API services ported in Phase 3
/// (forms-groups, templates, references, chat), plus the graph engine wired to
/// real entry data.
///
/// Read-only by design: it never creates, updates, or deletes anything in the
/// dev database. Skipped unless LIVE=true. See test/live/live_auth_test.dart.
///
///   flutter test test/live --dart-define=LIVE=true \
///     --dart-define=API_BASE_URL=http://localhost:8000
const bool _live = bool.fromEnvironment('LIVE');

void main() {
  group(
    'live professional API',
    () {
      late SessionStore session;
      late FormsGroupsApi formsGroups;
      late TemplatesApi templates;
      late ReferencesApi references;
      late ChatApi chat;

      setUpAll(() async {
        session = SessionStore(const FlutterSecureStorage())..seed({});
        final dio = buildDio(session);
        final auth = ProfessionalAuthApi(dio, session);

        final login = await auth.login(
          'nolan.performance@example.com',
          'ProfessionalScale!2026',
        );
        session.seed({SessionKeys.professionalToken: login.token});

        formsGroups = FormsGroupsApi(dio);
        templates = TemplatesApi(dio);
        references = ReferencesApi(dio);
        chat = ChatApi(dio);
      });

      test('forms-groups overview parses', () async {
        final overview = await formsGroups.getOverview();
        expect(overview.groups, isNotEmpty);
        expect(overview.maxGroups, greaterThan(0));

        final group = overview.groups.first;
        expect(group.id, greaterThan(0));
        expect(group.name, isNotEmpty);

        if (overview.hasLeadForm) {
          expect(overview.leadForm, isNotNull);
          expect(overview.leadForm!.fields, isNotEmpty);
          // Dynamic fields must carry a usable answer key.
          for (final field in overview.leadForm!.fields) {
            expect(field.answerKey, isNotEmpty);
          }
        }
      });

      test('templates parse, with fields and cadence', () async {
        final response = await templates.getTemplates();
        expect(response.maxTemplates, greaterThan(0));

        for (final template in response.templates) {
          expect(template.name, isNotEmpty);
          expect(template.cadence, isIn(TemplateCadenceValues.all));
          for (final field in template.fields) {
            expect(field.answerKey, isNotEmpty);
            expect(field.fieldType, isNotEmpty);
          }
        }
      });

      test('standard templates parse', () async {
        final standards = await templates.getStandardTemplates();
        expect(standards, isNotEmpty);
        expect(standards.first.key, isNotEmpty);
        expect(standards.first.fields, isNotEmpty);
      });

      test('references and categories parse', () async {
        final categories = await references.getCategories();
        final list = await references.getReferences();

        expect(list.usage.used, greaterThanOrEqualTo(0));
        for (final category in categories) {
          expect(category.name, isNotEmpty);
        }
        for (final reference in list.references) {
          expect(reference.title, isNotEmpty);
        }
      });

      test('group users parse', () async {
        final overview = await formsGroups.getOverview();
        final group = overview.groups.first;
        final users = await formsGroups.getGroupUsers(group.id);

        expect(users.group.id, group.id);
        for (final client in users.clients) {
          expect(client.username, isNotEmpty);
          expect(client.displayName, isNotEmpty);
        }
      });

      test('upcoming reminders + schedule summary parse', () async {
        final upcoming = await formsGroups.getUpcomingReminders();
        expect(upcoming.summary.totalPending, greaterThanOrEqualTo(0));
        expect(upcoming.summary.overdue, greaterThanOrEqualTo(0));
        for (final reminder in upcoming.reminders) {
          expect(reminder.title, isNotEmpty);
          expect(reminder.date, isNotEmpty);
        }
      });

      test('chat unread counts parse', () async {
        final unread = await chat.getProfessionalUnreadCounts();
        expect(unread.unreadCount, greaterThanOrEqualTo(0));
        // forClient() must not throw for an unknown client.
        expect(unread.forClient(999999), 0);
      });

      test('client detail parses for a real client', () async {
        final overview = await formsGroups.getOverview();
        final users = await formsGroups.getGroupUsers(overview.groups.first.id);
        if (users.clients.isEmpty) {
          markTestSkipped('no clients in the first group');
          return;
        }

        final detail = await formsGroups.getClientProfile(users.clients.first.id);
        expect(detail.client.id, users.clients.first.id);
        expect(detail.group.id, greaterThan(0));
      });

      test('client entries feed the graph engine end to end', () async {
        final overview = await formsGroups.getOverview();
        final users = await formsGroups.getGroupUsers(overview.groups.first.id);
        if (users.clients.isEmpty) {
          markTestSkipped('no clients in the first group');
          return;
        }
        final avaId = users.clients.first.id;
        final assignments = await templates.getAssignments(avaId);
        if (assignments.isEmpty) {
          markTestSkipped('no assignments for client 63');
          return;
        }

        final entries = await templates.getClientEntries(avaId);
        if (entries.isEmpty) {
          markTestSkipped('no entries for client 63');
          return;
        }

        final template = await templates.getTemplate(assignments.first.templateId);
        final fields = template.fields.map((f) => f.toFieldLike()).toList();
        final entryLikes = entries
            .where((e) => e.template == template.id)
            .map((e) => e.toEntryLike())
            .toList();

        if (entryLikes.isEmpty) {
          markTestSkipped('no entries for the first assigned template');
          return;
        }

        final charts = buildFieldCharts(fields, entryLikes, DateRange.all);
        // Every produced chart must be renderable: titled, and either has data
        // points or is a kind that legitimately has none (ring/summary).
        for (final chart in charts) {
          expect(chart.title, isNotEmpty);
          if (chart.kind != ChartKind.ring && chart.kind != ChartKind.summary) {
            expect(chart.data, isNotEmpty, reason: '${chart.kind} needs points');
          }
        }

        // The FIX #1 guarantee, on real data: no numeric series may contain a
        // phantom zero from an unanswered field.
        final stats = numericFieldStats(fields, entryLikes);
        for (final stat in stats.where((s) => s.hasData)) {
          expect(stat.count, greaterThan(0));
        }
      });
    },
    skip: _live ? false : 'live backend test — run with --dart-define=LIVE=true',
  );
}

/// Local mirror of the cadence values, to keep the test independent of the
/// class name used in template_models.dart.
class TemplateCadenceValues {
  static const all = ['daily', 'weekly', 'monthly'];
}
