// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/partner.dart';
import '../../../services/supabase/partner_repo.dart';

// Nuove pagine modularizzate
import 'pages/dashboard_page.dart';
import 'pages/prenotazioni_page.dart';
import 'pages/scanner_page.dart';
import 'pages/spazi_page.dart';
import 'pages/profilo_page.dart';

// Schermate esterne
import '../auth_partner/partner_registration_screen.dart';
import '../auth_partner/partner_waiting_screen.dart';
import '../../autenticazione/auth_actions.dart';
import '../auth_partner/partner_application_screen.dart';


// ✅ NUOVO: drawer condiviso + scope
import '../user_view/partner_drawer.dart';

class PartnerShell extends StatefulWidget {
  const PartnerShell({super.key});

  @override
  State<PartnerShell> createState() => _PartnerShellState();
}

class _PartnerShellState extends State<PartnerShell> {
  Partner? _partner;
  bool _loading = true;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _loadPartner();
  }

  Future<void> _loadPartner() async {
    setState(() => _loading = true);
    final repo = PartnerRepo(Supabase.instance.client);

    try {
      final p = await repo.getMyPartner();
      if (!mounted) return;

      setState(() {
        _partner = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _reload() => _loadPartner();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final p = _partner;
    final user = Supabase.instance.client.auth.currentUser;

    // Nessun partner: non esiste alcuna attività collegata => non mostro la dashboard partner
    // (da qui in poi la richiesta verrà fatta dal sito)
    if (p == null) {
      return const PartnerApplicationScreen();
    }


    // Pending / Rejected
    if (p.isPending || p.isRejected) {
      return PartnerWaitingScreen(partner: p, onReapplyCompleted: _reload);
    }

    // Partner approvato → tutte le pagine abilitate
    return _buildShell(
      user: user,
      partner: p,
      pages: [
        DashboardPage(partner: p, onPartnerChanged: _reload),
        PrenotazioniPage(partner: p),
        const ScannerPage(),
        const SpaziPage(),
        ProfiloPage(partner: p, onPartnerChanged: _reload),
      ],
    );
  }

  Widget _buildShell({
    required List<Widget> pages,
    required Partner? partner,
    required User? user,
  }) {
    // ✅ Niente Scaffold + niente BottomNavigationBar.
    // Manteniamo l’indice e lo esponiamo via scope al Drawer.
    return PartnerShellScope(
      partner: partner,
      user: user,
      index: _index,
      reloadPartner: _reload,
      setIndex: (i) => setState(() => _index = i),
      child: pages[_index],
    );
  }
}
