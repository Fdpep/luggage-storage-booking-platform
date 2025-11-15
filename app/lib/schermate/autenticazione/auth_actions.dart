import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class AuthActions {
  static Future<bool> confirmAndLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Conferma logout'),
          content: const Text('Vuoi davvero disconnetterti dal tuo account?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false); // annulla
              },
              child: const Text('Annulla'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(true); // conferma
              },
              child: const Text('Disconnetti'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      // utente ha annullato o chiuso il dialog
      return false;
    }

    try {
      await Supabase.instance.client.auth.signOut();
      return true;
    } catch (e) {
      debugPrint('[Logout] signOut error: $e');
      // volendo puoi mostrare uno snackBar di errore qui
      return false;
    }
  }
}
