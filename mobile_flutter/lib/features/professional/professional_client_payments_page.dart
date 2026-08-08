import 'package:flutter/material.dart';

import 'widgets/client_payments_panel.dart';

/// Deep-link target for the Dashboard's "Needs action" payment list (see
/// professional_dashboard_page.dart, `/payments?name=`). The client-detail
/// page's Payments tab renders [ClientPaymentsPanel] inline instead of
/// navigating here, so this page now only exists as a thin Scaffold wrapper
/// around the same shared, embeddable panel.
class ProfessionalClientPaymentsPage extends StatelessWidget {
  const ProfessionalClientPaymentsPage({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  final int clientId;
  final String clientName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$clientName · Payments')),
      body: ClientPaymentsPanel(clientId: clientId, clientName: clientName),
    );
  }
}
