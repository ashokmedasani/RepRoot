import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/config/env.dart';
import '../../core/constants/location_options.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Professional profile — view/edit the full profile and the Private/Public
/// visibility of each section.
/// Replica of mobile/src/app/pages/professional/profile/professional-profile.page.ts.
class ProfessionalProfilePage extends ConsumerStatefulWidget {
  const ProfessionalProfilePage({super.key});

  @override
  ConsumerState<ProfessionalProfilePage> createState() =>
      _ProfessionalProfilePageState();
}

/// The six Private/Public sections the web professional profile exposes.
/// The keys are the backend's, and `certification` is singular on purpose —
/// sending `certifications` silently does nothing.
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DioMediaType _profileImageMediaType(String filename) {
  final extension = filename.split('.').last.toLowerCase();
  return switch (extension) {
    'png' => DioMediaType('image', 'png'),
    'webp' => DioMediaType('image', 'webp'),
    'gif' => DioMediaType('image', 'gif'),
    'heic' || 'heif' => DioMediaType('image', 'heic'),
    _ => DioMediaType('image', 'jpeg'),
  };
}

class _ProfileLinkEditor {
  _ProfileLinkEditor({String title = '', String url = ''})
    : title = TextEditingController(text: title),
      url = TextEditingController(text: url);

  final TextEditingController title;
  final TextEditingController url;

  void dispose() {
    title.dispose();
    url.dispose();
  }
}

class _ProfileImageEditor {
  _ProfileImageEditor({
    this.category = 'Certificates',
    String title = '',
    this.url = '',
  }) : title = TextEditingController(text: title);

  String category;
  final TextEditingController title;
  String url;

  void dispose() => title.dispose();
}

class _ProfessionalProfilePageState
    extends ConsumerState<ProfessionalProfilePage> {
  ProfessionalProfile? _profile;
  Map<String, bool> _visibility = {};
  bool _isEditing = false;
  bool _isSaving = false;
  bool _loading = true;
  String _message = '';
  bool _messageIsError = false;
  XFile? _photoFile;
  Uint8List? _photoPreviewBytes;
  bool _isRemovingPhoto = false;
  String? _certificationFilePath;
  String _certificationFileName = '';

  // Edit fields
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _professionalCode = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController();
  final _state = TextEditingController();
  final _headline = TextEditingController();
  final _aboutMe = TextEditingController();
  final _professionalType = TextEditingController();
  final _specializations = TextEditingController();
  final _trainingStyle = TextEditingController();
  final _languages = TextEditingController();
  final _yearsExperience = TextEditingController();
  final _certName = TextEditingController();
  final _certIssuedBy = TextEditingController();
  final _certYear = TextEditingController();
  final _instagram = TextEditingController();
  final _youtube = TextEditingController();
  final _website = TextEditingController();
  final List<_ProfileLinkEditor> _profileLinks = [];
  final List<_ProfileImageEditor> _profileImages = [];
  String _gender = '';
  int? _birthMonth;
  int? _birthYear;

  static const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];
  static const _imageCategories = [
    'Certificates',
    'Transformation Photos',
    'Achievements',
    'Body Physique',
    'Other Images',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _middleName,
      _lastName,
      _username,
      _professionalCode,
      _phone,
      _country,
      _state,
      _headline,
      _aboutMe,
      _professionalType,
      _specializations,
      _trainingStyle,
      _languages,
      _yearsExperience,
      _certName,
      _certIssuedBy,
      _certYear,
      _instagram,
      _youtube,
      _website,
    ]) {
      c.dispose();
    }
    for (final link in _profileLinks) {
      link.dispose();
    }
    for (final image in _profileImages) {
      image.dispose();
    }
    super.dispose();
  }

  String get _initials {
    final first = _profile?.firstName ?? '';
    final last = _profile?.lastName ?? '';
    final letters =
        '${first.isNotEmpty ? first[0] : ''}${last.isNotEmpty ? last[0] : ''}'
            .toUpperCase();
    return letters.isEmpty ? 'T' : letters;
  }

  List<int> get _years {
    final now = DateTime.now().year;
    return List.generate(83, (i) => now - 18 - i);
  }

  Future<void> _load() async {
    try {
      final profile = await ref.read(professionalAuthApiProvider).getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _visibility = {...profile.profileVisibility};
        _fillControllers(profile);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load your profile.';
        _messageIsError = true;
        _loading = false;
      });
    }
  }

  void _fillControllers(ProfessionalProfile p) {
    _firstName.text = p.firstName;
    _middleName.text = p.middleName;
    _lastName.text = p.lastName;
    _username.text = p.username;
    _professionalCode.text = p.professionalId.isNotEmpty
        ? p.professionalId
        : p.professionalCode;
    _phone.text = p.phone;
    final country = p.country.trim().toUpperCase();
    _country.text = country == 'IN' || country == 'INDIA'
        ? 'India'
        : country == 'US' ||
              country == 'USA' ||
              country.startsWith('UNITED STATES')
        ? 'United States'
        : p.country;
    _state.text = p.state;
    _headline.text = p.professionalHeadline;
    _aboutMe.text = p.aboutMe;
    _professionalType.text = p.professionalType;
    _specializations.text = p.specializations;
    _trainingStyle.text = p.trainingStyle;
    _languages.text = p.languagesKnown;
    _yearsExperience.text = p.yearsExperience?.toString() ?? '';
    _certName.text = p.certificationName;
    _certIssuedBy.text = p.certificationIssuedBy;
    _certYear.text = p.certificationYear?.toString() ?? '';
    _instagram.text = p.instagramUrl;
    _youtube.text = p.youtubeUrl;
    _website.text = p.websiteUrl;
    for (final link in _profileLinks) {
      link.dispose();
    }
    _profileLinks
      ..clear()
      ..addAll(
        p.profileLinks.map(
          (link) => _ProfileLinkEditor(title: link.title, url: link.url),
        ),
      );
    for (final image in _profileImages) {
      image.dispose();
    }
    _profileImages
      ..clear()
      ..addAll(
        p.profileImages.map(
          (image) => _ProfileImageEditor(
            category: _imageCategories.contains(image.category)
                ? image.category
                : 'Other Images',
            title: image.title,
            url: image.url,
          ),
        ),
      );
    _gender = _genders.contains(p.gender) ? p.gender : '';
    _birthMonth = p.birthMonth;
    _birthYear = p.birthYear;
  }

  void _setMessage(String text, bool isError) {
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = '');
    });
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoFile = picked;
      _photoPreviewBytes = bytes;
    });
  }

  void _discardPickedPhoto() {
    if (_photoFile == null && _photoPreviewBytes == null) return;
    setState(() {
      _photoFile = null;
      _photoPreviewBytes = null;
    });
  }

  Future<void> _pickProfileImage(int index) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (picked == null || index >= _profileImages.length) return;

    final bytes = await picked.readAsBytes();
    final extension = picked.name.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    if (!mounted) return;
    setState(() {
      final image = _profileImages[index];
      image.url = 'data:$mime;base64,${base64Encode(bytes)}';
      if (image.title.text.trim().isEmpty) image.title.text = picked.name;
    });
  }

  /// Deletes the saved photo immediately rather than on Save — it's its own
  /// endpoint, and the multipart save treats "no file" as "keep the current
  /// one", so there is no way to express removal through the normal save.
  Future<void> _removePhoto() async {
    if (_isRemovingPhoto) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text(
          'Your profile will show your initials instead. You can upload a new '
          'photo at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRemovingPhoto = true);
    try {
      final updated = await ref
          .read(professionalAuthApiProvider)
          .removeProfilePhoto();
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _photoFile = null;
        _photoPreviewBytes = null;
        _isRemovingPhoto = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRemovingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove the photo.')),
      );
    }
  }

  Future<void> _pickCertificationFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
    );
    final file = result?.files.single;
    if (!mounted || file?.path == null) return;
    setState(() {
      _certificationFilePath = file!.path;
      _certificationFileName = file.name;
    });
  }

  Future<void> _save() async {
    final profile = _profile;
    if (profile == null) return;

    // The same required set the web portal enforces on first login.
    final missing = <String>[
      if (_firstName.text.trim().isEmpty) 'first name',
      if (_lastName.text.trim().isEmpty) 'last name',
      if (_username.text.trim().isEmpty) 'username',
      if (_professionalCode.text.trim().isEmpty) 'professional code',
      if (_gender.isEmpty) 'gender',
      if (_birthMonth == null) 'birth month',
      if (_birthYear == null) 'birth year',
      if (_country.text.trim().isEmpty) 'country',
      if (_state.text.trim().isEmpty) 'state',
    ];
    if (missing.isNotEmpty) {
      _setMessage('Required: ${missing.join(', ')}.', true);
      return;
    }

    setState(() => _isSaving = true);

    final map = <String, dynamic>{
      'professional_id': _professionalCode.text.trim(),
      'username': _username.text.trim().toLowerCase(),
      'first_name': _firstName.text.trim(),
      'middle_name': _middleName.text.trim(),
      'last_name': _lastName.text.trim(),
      'phone': _phone.text.trim(),
      'gender': _gender,
      'country': _country.text.trim(),
      'state': _state.text.trim(),
      'professional_headline': _headline.text.trim(),
      'about_me': _aboutMe.text.trim(),
      'professional_type': _professionalType.text.trim(),
      'specializations': _specializations.text.trim(),
      'training_style': _trainingStyle.text.trim(),
      'languages_known': _languages.text.trim(),
      'certification_name': _certName.text.trim(),
      'certification_issued_by': _certIssuedBy.text.trim(),
      'intro_video_url': profile.introVideoUrl,
      'instagram_url': _instagram.text.trim(),
      'youtube_url': _youtube.text.trim(),
      'website_url': _website.text.trim(),
      'profile_links': jsonEncode([
        for (final link in _profileLinks)
          if (link.title.text.trim().isNotEmpty &&
              link.url.text.trim().isNotEmpty)
            {'title': link.title.text.trim(), 'url': link.url.text.trim()},
      ]),
      'profile_images': jsonEncode([
        for (final image in _profileImages)
          if (image.title.text.trim().isNotEmpty && image.url.isNotEmpty)
            {
              'category': image.category,
              'title': image.title.text.trim(),
              'url': image.url,
            },
      ]),
      'birth_month': '$_birthMonth',
      'birth_year': '$_birthYear',
    };

    // Numbers are omitted when blank rather than sent empty, matching the TS.
    if (_yearsExperience.text.trim().isNotEmpty) {
      map['years_experience'] = _yearsExperience.text.trim();
    }
    if (_certYear.text.trim().isNotEmpty) {
      map['certification_year'] = _certYear.text.trim();
    }
    if (_photoFile != null) {
      map['profile_photo'] = MultipartFile.fromBytes(
        await _photoFile!.readAsBytes(),
        filename: _photoFile!.name,
        contentType: _profileImageMediaType(_photoFile!.name),
      );
    }
    if (_certificationFilePath != null) {
      map['certification_file'] = await MultipartFile.fromFile(
        _certificationFilePath!,
        filename: _certificationFileName,
      );
    }

    try {
      final saved = await ref
          .read(professionalAuthApiProvider)
          .saveProfile(FormData.fromMap(map));
      if (!mounted) return;
      setState(() {
        _profile = saved;
        _visibility = saved.profileVisibility.isNotEmpty
            ? {...saved.profileVisibility}
            : _visibility;
        _isSaving = false;
        _isEditing = false;
        _photoFile = null;
        _photoPreviewBytes = null;
        _certificationFilePath = null;
        _certificationFileName = '';
        _fillControllers(saved);
      });
      _setMessage('Profile saved.', false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _setMessage(error.message, true);
    }
  }

  /// Sends the whole map every time. The backend resets any key it does not
  /// receive to false, so a partial PUT silently hides other sections.
  Future<void> _toggleVisibility(String key, bool value) async {
    final previous = {..._visibility};
    setState(() => _visibility = {..._visibility, key: value});
    try {
      final updated = await ref
          .read(professionalAuthApiProvider)
          .updateProfileVisibility(_visibility);
      if (mounted) setState(() => _visibility = updated);
    } catch (_) {
      // Put the switch back rather than leaving the UI lying about the server.
      if (mounted) setState(() => _visibility = previous);
      _setMessage('Could not update visibility.', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Account')),
        body: const PagePad(
          children: [SkeletonBox(height: 110), SkeletonBox(height: 200)],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.professionalMore);
            }
          },
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit profile',
            ),
        ],
      ),
      body: PagePad(
        onRefresh: _isEditing ? null : _load,
        children: [
          if (_message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                color:
                    (_messageIsError
                            ? context.colors.error
                            : context.tokens.success)
                        .withValues(alpha: 0.08),
                child: Text(
                  _message,
                  style: context.text.bodySmall?.copyWith(
                    color: _messageIsError
                        ? context.colors.error
                        : context.tokens.success,
                  ),
                ),
              ),
            ),
          if (_isEditing) _editor() else _viewer(),
        ],
      ),
    );
  }

  Widget _viewer() {
    final p = _profile!;

    return Column(
      children: [
        AppCard(
          child: Row(
            children: [
              AppAvatar(
                initials: _initials,
                imageUrl: Env.mediaUrl(p.profilePhotoUrl),
                size: 60,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.displayName.isEmpty ? p.username : p.displayName,
                      style: context.text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.professionalHeadline.isEmpty
                          ? 'Personal Professional'
                          : p.professionalHeadline,
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    StatusPill(
                      label:
                          'Code: ${p.professionalId.isNotEmpty ? p.professionalId : p.professionalCode}',
                      tone: PillTone.info,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Account details have no visibility key on the backend — they are
        // never shown to clients — so this is the one section without a
        // control.
        const SectionHeader(title: 'Details'),
        AppCard(
          child: Column(
            children: [
              _kv('Email', p.email),
              _kv('Username', p.username),
              _kv('Phone', p.phone),
              _kv('Gender', p.gender),
              _kv(
                'Born',
                p.birthMonth != null && p.birthYear != null
                    ? '${_months[p.birthMonth! - 1]} ${p.birthYear}'
                    : '',
              ),
              _kv(
                'Location',
                [p.state, p.country].where((s) => s.isNotEmpty).join(', '),
              ),
            ],
          ),
        ),

        // From here down, every section carries its own Private / Public
        // control, exactly as the web's `.read-card > .card-head` does. The
        // single "Client visibility" panel that used to hold ten switches is
        // gone: it listed section names far away from the sections they
        // governed, so setting one meant remembering which content it meant.
        _visibilitySection(
          title: 'Professional details',
          visibilityKey: 'professional_summary',
          children: [
            _kv('Type', p.professionalType),
            _kv(
              'Experience',
              p.yearsExperience != null ? '${p.yearsExperience} years' : '',
            ),
          ],
        ),

        if (p.specializations.trim().isNotEmpty)
          _visibilitySection(
            title: 'Specializations',
            visibilityKey: 'specializations',
            children: [Text(p.specializations, style: context.text.bodyMedium)],
          ),

        if (p.languagesKnown.trim().isNotEmpty)
          _visibilitySection(
            title: 'Languages',
            visibilityKey: 'languages',
            children: [Text(p.languagesKnown, style: context.text.bodyMedium)],
          ),

        if (p.aboutMe.trim().isNotEmpty)
          _visibilitySection(
            title: 'About me',
            visibilityKey: 'about',
            children: [Text(p.aboutMe, style: context.text.bodyMedium)],
          ),

        if (p.trainingStyle.trim().isNotEmpty)
          _visibilitySection(
            title: 'Training style',
            visibilityKey: 'training_style',
            children: [Text(p.trainingStyle, style: context.text.bodyMedium)],
          ),

        if (p.certificationName.trim().isNotEmpty ||
            p.certificationIssuedBy.trim().isNotEmpty)
          _visibilitySection(
            title: 'Certification',
            visibilityKey: 'certification',
            children: [
              _kv('Name', p.certificationName),
              _kv('Issued by', p.certificationIssuedBy),
              _kv('Year', p.certificationYear?.toString() ?? ''),
            ],
          ),

        if (p.profileImages.isNotEmpty)
          _visibilitySection(
            title: 'Images',
            visibilityKey: 'images',
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final image in p.profileImages)
                    SizedBox(
                      width: 132,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: AppRadius.controlAll,
                            child: SizedBox(
                              width: 132,
                              height: 96,
                              child: _profileImage(image.url),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            image.title,
                            style: context.text.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (image.category.isNotEmpty)
                            Text(
                              image.category,
                              style: context.text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

        if (p.profileLinks.isNotEmpty)
          _visibilitySection(
            title: 'Links',
            visibilityKey: 'links',
            children: [
              for (final link in p.profileLinks) _kv(link.title, link.url),
            ],
          ),
      ],
    );
  }

  Widget _profileImage(String source) {
    final fallback = ColoredBox(
      color: context.tokens.surfaceSoft,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: context.tokens.muted,
          size: AppSize.iconRow,
        ),
      ),
    );
    if (source.startsWith('data:image/')) {
      try {
        final comma = source.indexOf(',');
        if (comma < 0) return fallback;
        return Image.memory(
          base64Decode(source.substring(comma + 1)),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
      } catch (_) {
        return fallback;
      }
    }
    final url = Env.mediaUrl(source);
    if (url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }

  /// One profile section with its visibility control in the heading — the
  /// web's `card-head` pattern. [visibilityKey] is the backend
  /// `profile_visibility` key; both platforms write the same map.
  Widget _visibilitySection({
    required String title,
    required String visibilityKey,
    required List<Widget> children,
  }) {
    final isPublic = _visibility[visibilityKey] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: SectionHeader(title: title)),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _VisibilityChip(
                isPublic: isPublic,
                onChanged: (value) => _toggleVisibility(visibilityKey, value),
              ),
            ),
          ],
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: context.text.bodySmall)),
          Expanded(
            flex: 3,
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: context.text.titleSmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    return Column(
      children: [
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  AppAvatar(
                    initials: _initials,
                    imageUrl: _photoFile == null
                        ? Env.mediaUrl(_profile?.profilePhotoUrl ?? '')
                        : '',
                    imageBytes: _photoPreviewBytes,
                    size: 56,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(
                            Icons.photo_camera_outlined,
                            size: AppSize.iconRow,
                          ),
                          label: const Text('Change photo'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, AppSize.buttonHeightSm),
                          ),
                        ),
                        if (_photoFile != null)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              _photoFile!.name,
                              style: context.text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (_photoFile != null)
                          TextButton.icon(
                            onPressed: _discardPickedPhoto,
                            icon: const Icon(
                              Icons.close,
                              size: AppSize.iconRow,
                            ),
                            label: const Text('Discard new photo'),
                            style: TextButton.styleFrom(
                              foregroundColor: context.colors.error,
                              minimumSize: const Size(
                                0,
                                AppSize.buttonHeightSm,
                              ),
                            ),
                          ),
                        // Only offered when there is a saved photo to remove —
                        // an unsaved pick is cleared with Cancel instead.
                        if (_photoFile == null &&
                            (_profile?.profilePhotoUrl ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: TextButton.icon(
                              onPressed: _isRemovingPhoto ? null : _removePhoto,
                              icon: const Icon(
                                Icons.delete_outline,
                                size: AppSize.iconRow,
                              ),
                              label: Text(
                                _isRemovingPhoto ? 'Removing…' : 'Remove photo',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: context.colors.error,
                                minimumSize: const Size(
                                  0,
                                  AppSize.buttonHeightSm,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        _editSection('Basic Profile', [
          _field(_firstName, 'First name', capitalize: true),
          _field(_middleName, 'Middle name (optional)', capitalize: true),
          _field(_lastName, 'Last name', capitalize: true),
          _field(
            _username,
            'Username',
            helper: 'Used with your email when signing in',
          ),
          _field(_phone, 'Phone', keyboard: TextInputType.phone),
          DropdownButtonFormField<String>(
            initialValue: _gender.isEmpty ? null : _gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: _genders
                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                .toList(),
            onChanged: (v) => setState(() => _gender = v ?? ''),
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _birthMonth,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Birth month'),
                  items: [
                    for (var i = 0; i < _months.length; i++)
                      DropdownMenuItem(value: i + 1, child: Text(_months[i])),
                  ],
                  onChanged: (v) => setState(() => _birthMonth = v),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _birthYear,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Birth year'),
                  items: _years
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: (v) => setState(() => _birthYear = v),
                ),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: professionalCountries.contains(_country.text)
                ? _country.text
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Country'),
            items: professionalCountries
                .map(
                  (country) =>
                      DropdownMenuItem(value: country, child: Text(country)),
                )
                .toList(),
            onChanged: (value) => setState(() {
              _country.text = value ?? '';
              if (!(professionalStates[value] ?? const <String>[]).contains(
                _state.text,
              )) {
                _state.clear();
              }
            }),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('${_country.text}:${_state.text}'),
            initialValue:
                (professionalStates[_country.text] ?? const <String>[])
                    .contains(_state.text)
                ? _state.text
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'State'),
            items: (professionalStates[_country.text] ?? const <String>[])
                .map(
                  (state) => DropdownMenuItem(value: state, child: Text(state)),
                )
                .toList(),
            onChanged: _country.text.isEmpty
                ? null
                : (value) => setState(() => _state.text = value ?? ''),
          ),
          _field(_headline, 'Professional headline'),
          _field(_aboutMe, 'About me', lines: 4),
        ]),

        _editSection('Professional Details', [
          _field(_professionalType, 'Professional type'),
          _field(
            _yearsExperience,
            'Years of experience',
            keyboard: TextInputType.number,
          ),
          _field(_specializations, 'Specializations'),
          _field(_languages, 'Languages known'),
          _field(_trainingStyle, 'Training style', lines: 3),
        ]),

        _editSection('Certifications', [
          _field(_certName, 'Certification name'),
          _field(_certIssuedBy, 'Issued by'),
          _field(_certYear, 'Year', keyboard: TextInputType.number),
          AppCard(
            color: context.tokens.surfaceSoft,
            elevated: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Certification document', style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _certificationFileName.isNotEmpty
                      ? _certificationFileName
                      : (_profile?.certificationFileUrl ?? '').isNotEmpty
                      ? 'A certification document is already saved.'
                      : 'Add a PDF or image, up to 10 MB.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _pickCertificationFile,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    (_profile?.certificationFileUrl ?? '').isNotEmpty ||
                            _certificationFileName.isNotEmpty
                        ? 'Replace document'
                        : 'Choose document',
                  ),
                ),
              ],
            ),
          ),
        ]),

        _editSection('Images', [
          for (var index = 0; index < _profileImages.length; index++)
            AppCard(
              color: context.tokens.surfaceSoft,
              elevated: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Image ${index + 1}',
                          style: context.text.titleSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          final removed = _profileImages.removeAt(index);
                          removed.dispose();
                        }),
                        tooltip: 'Remove image',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  ClipRRect(
                    borderRadius: AppRadius.controlAll,
                    child: SizedBox(
                      width: double.infinity,
                      height: 150,
                      child: _profileImage(_profileImages[index].url),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _profileImages[index].category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _imageCategories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(
                      () => _profileImages[index].category =
                          value ?? 'Other Images',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _field(_profileImages[index].title, 'Title'),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => _pickProfileImage(index),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _profileImages[index].url.isEmpty
                          ? 'Choose image'
                          : 'Replace image',
                    ),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _profileImages.add(_ProfileImageEditor())),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add image'),
          ),
        ]),

        _editSection('Links', [
          for (var index = 0; index < _profileLinks.length; index++)
            AppCard(
              color: context.tokens.surfaceSoft,
              elevated: false,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Link ${index + 1}',
                          style: context.text.titleSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          final removed = _profileLinks.removeAt(index);
                          removed.dispose();
                        }),
                        tooltip: 'Remove link',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _field(_profileLinks[index].title, 'Link name'),
                  const SizedBox(height: AppSpacing.sm),
                  _field(
                    _profileLinks[index].url,
                    'URL',
                    keyboard: TextInputType.url,
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () =>
                setState(() => _profileLinks.add(_ProfileLinkEditor())),
            icon: const Icon(Icons.add_link),
            label: const Text('Add profile link'),
          ),
        ]),

        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? 'Saving…' : 'Save profile'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: _isSaving
                  ? null
                  : () => setState(() {
                      _isEditing = false;
                      _photoFile = null;
                      _photoPreviewBytes = null;
                      if (_profile != null) _fillControllers(_profile!);
                    }),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _editSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.md),
            for (final child in children)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: child,
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    int lines = 1,
    TextInputType? keyboard,
    bool capitalize = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: lines,
      keyboardType: keyboard,
      autocorrect: !capitalize,
      textCapitalization: capitalize
          ? TextCapitalization.words
          : TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, helperText: helper),
    );
  }
}

/// The web's `.visibility-toggle`: a two-state Private / Public pair, sized to
/// sit inline in a section heading.
///
/// "Public" rather than "Visible to clients" because that is the word the
/// website uses, and a professional's public profile is genuinely public —
/// it is what prospects see on a lead form, not only existing clients.
class _VisibilityChip extends StatelessWidget {
  const _VisibilityChip({required this.isPublic, required this.onChanged});

  final bool isPublic;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    Widget half(String label, bool value) {
      final selected = isPublic == value;
      return InkWell(
        onTap: selected ? null : () => onChanged(value),
        borderRadius: AppRadius.pillAll,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: selected ? context.colors.surface : Colors.transparent,
            borderRadius: AppRadius.pillAll,
            boxShadow: selected ? tokens.shadowSm : null,
          ),
          child: Text(
            label,
            style: context.text.labelSmall?.copyWith(
              color: selected ? context.colors.primary : tokens.muted,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [half('Private', false), half('Public', true)],
      ),
    );
  }
}
