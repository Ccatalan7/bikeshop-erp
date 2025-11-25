import 'package:flutter/material.dart';

import '../../../shared/widgets/main_layout.dart';
import '../widgets/pegas_calendar_widget.dart';

/// Standalone calendar page for workshop jobs
/// Uses the shared PegasCalendarWidget
class WorkshopCalendarPage extends StatelessWidget {
  const WorkshopCalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainLayout(
      title: 'Calendario de Taller',
      child: PegasCalendarWidget(),
    );
  }
}
