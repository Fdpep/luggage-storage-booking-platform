// lib/schermate/partner/partner_photos_screen.dart


import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_storage.dart';

/// Schermata per gestire le foto del locale:
/// - mostra tutte le foto del partner
/// - permette di aggiungere nuove foto
/// - permette di impostare la copertina
/// - permette di eliminare una foto
class PartnerPhotosScreen extends StatefulWidget {
  final Partner partner;

  const PartnerPhotosScreen({
    super.key,
    required this.partner,
  });

  @override
  State<PartnerPhotosScreen> createState() => _PartnerPhotosScreenState();
}

class _PartnerPhotosScreenState extends State<PartnerPhotosScreen> {
  final _photoRepo = const PartnerPhotoRepo();
  final _storage = const PartnerPhotoStorage();
  final _picker = ImagePicker();

  List<PartnerPhoto> _photos = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  String? _savingCoverId;
  String? _deletingId;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  /// Carica tutte le foto del partner da Supabase.
  Future<void> _loadPhotos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final photos =
          await _photoRepo.fetchPhotosForPartner(widget.partner.id);

      if (!mounted) return;
      setState(() {
        _photos = photos;
        _loading = false;
        _error = null;
      });
    } catch (e, st) {
      debugPrint('Errore _loadPhotos: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Errore durante il caricamento delle foto.';
      });
    }
  }

  /// Apre la galleria, carica l'immagine su Storage tramite PartnerPhotoStorage
  /// e inserisce il metadato in partner_photos.
  Future<void> _addPhoto() async {
    if (_uploading) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );

    if (picked == null) return; // utente ha annullato

    setState(() {
      _uploading = true;
    });

    try {

           // Leggiamo i bytes dall'immagine selezionata
     final bytes = await picked.readAsBytes();

     // Nome file (usa quello originale, eventualmente preceduto da timestamp)
     final originalName = picked.name; // es. "image.jpg"
     final fileName =
         '${DateTime.now().millisecondsSinceEpoch}_$originalName';

     // Content-Type semplice in base all'estensione
     final ext = originalName.split('.').last.toLowerCase();
     String contentType;
     if (ext == 'png') {
       contentType = 'image/png';
     } else {
       // default jpg/jpeg
       contentType = 'image/jpeg';
     }

     // Upload su Supabase Storage → otteniamo l'URL pubblico
     final String publicUrl = await _storage.uploadPartnerPhoto(
       partnerId: widget.partner.id,
       fileName: fileName,
       bytes: bytes,
       contentType: contentType,
     );


      final bool isFirst = _photos.isEmpty;

      await _photoRepo.insertPhoto(
        partnerId: widget.partner.id,
        url: publicUrl,
        isCover: isFirst,               // la prima foto diventa cover
        sortOrder: _photos.length,      // in coda
      );

      await _loadPhotos();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto caricata.')),
      );
    } catch (e, st) {
      debugPrint('Errore _addPhoto: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante il caricamento della foto.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  /// Imposta una foto come copertina:
  /// - mette is_cover = true per questa foto
  /// - mette is_cover = false per tutte le altre.
  Future<void> _setAsCover(PartnerPhoto photo) async {
    if (_savingCoverId != null) return;

    setState(() {
      _savingCoverId = photo.id;
    });

    try {
      for (final p in _photos) {
        final bool newCover = p.id == photo.id;
        if (p.isCover == newCover) continue;

        await _photoRepo.updatePhoto(
          photoId: p.id,
          isCover: newCover,
        );
      }

      await _loadPhotos();
    } catch (e, st) {
      debugPrint('Errore _setAsCover: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante l’aggiornamento della copertina.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingCoverId = null;
        });
      }
    }
  }

  /// Elimina una foto (solo metadati, non per forza lo Storage).
  Future<void> _deletePhoto(PartnerPhoto photo) async {
    if (_deletingId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina foto'),
        content: const Text(
          'Vuoi davvero eliminare questa foto dal tuo profilo attività?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _deletingId = photo.id;
    });

    try {
      await _photoRepo.deletePhoto(photo.id);

      // In futuro puoi anche eliminare il file dallo Storage:
      // await _storage.deleteFromStorage(photo.url);

      await _loadPhotos();
    } catch (e, st) {
      debugPrint('Errore _deletePhoto: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante l’eliminazione della foto.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _deletingId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Foto del locale'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _photos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Non hai ancora caricato foto.\n'
                          'Usa il pulsante in basso a destra per aggiungerne.',
                          textAlign: TextAlign.center,
                          style: tt.bodyMedium,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _photos.length,
                      itemBuilder: (ctx, index) {
                        final photo = _photos[index];
                        final isCover = photo.isCover;
                        final busy =
                            _savingCoverId == photo.id || _deletingId == photo.id;

                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                photo.url,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            // Badge "COVER"
                            if (isCover)
                              Positioned(
                                left: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'COPERTINA',
                                    style: tt.labelSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            // Menu azioni
                            Positioned(
                              right: 0,
                              top: 0,
                              child: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'cover') {
                                    _setAsCover(photo);
                                  } else if (value == 'delete') {
                                    _deletePhoto(photo);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  if (!isCover)
                                    const PopupMenuItem(
                                      value: 'cover',
                                      child: Text('Imposta come copertina'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Elimina'),
                                  ),
                                ],
                              ),
                            ),
                            if (busy)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _addPhoto,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(_uploading ? 'Carico...' : 'Aggiungi foto'),
      ),
    );
  }
}
