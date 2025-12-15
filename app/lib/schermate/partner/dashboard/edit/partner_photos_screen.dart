import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_storage.dart';

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

  Future<void> _loadPhotos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final photos = await _photoRepo.fetchPhotosForPartner(widget.partner.id);

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

  Future<void> _addPhoto() async {
    if (_uploading) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );

    if (picked == null) return;

    setState(() => _uploading = true);

    try {
      final bytes = await picked.readAsBytes();
      final originalName = picked.name;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$originalName';

      final ext = originalName.split('.').last.toLowerCase();
      final contentType = (ext == 'png') ? 'image/png' : 'image/jpeg';

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
        isCover: isFirst,
        sortOrder: _photos.length,
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
        const SnackBar(content: Text('Errore durante il caricamento della foto.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _setAsCover(PartnerPhoto photo) async {
    if (_savingCoverId != null) return;

    setState(() => _savingCoverId = photo.id);

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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copertina aggiornata.')),
      );
    } catch (e, st) {
      debugPrint('Errore _setAsCover: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante l’aggiornamento della copertina.')),
      );
    } finally {
      if (mounted) setState(() => _savingCoverId = null);
    }
  }

  Future<void> _deletePhoto(PartnerPhoto photo) async {
    if (_deletingId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina foto'),
        content: const Text('Vuoi davvero eliminare questa foto dal tuo profilo attività?'),
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

    setState(() => _deletingId = photo.id);

    try {
      await _photoRepo.deletePhoto(photo.id);
      await _loadPhotos();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto eliminata.')),
      );
    } catch (e, st) {
      debugPrint('Errore _deletePhoto: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante l’eliminazione della foto.')),
      );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('Foto del locale'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                  children: [
                    _HeaderCard(
                      title: widget.partner.name,
                      subtitle: _photos.isEmpty
                          ? 'Nessuna foto caricata'
                          : '${_photos.length} foto • Tocca una foto per le opzioni',
                    ),
                    const SizedBox(height: 12),

                    if (_photos.isEmpty)
                      _EmptyState(
                        onAdd: _uploading ? null : _addPhoto,
                        uploading: _uploading,
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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

                          return _PhotoTile(
                            url: photo.url,
                            isCover: isCover,
                            busy: busy,
                            onMenu: () => _openActionsSheet(photo),
                          );
                        },
                      ),
                  ],
                ),

      // ✅ CTA moderna fissa in basso (coerente col resto dell’app)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _uploading ? null : _addPhoto,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              label: Text(_uploading ? 'Caricamento…' : 'Aggiungi foto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openActionsSheet(PartnerPhoto photo) {
    final isCover = photo.isCover;
    final busy = _savingCoverId != null || _deletingId != null;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.star_outline, color: cs.primary),
                  title: const Text('Imposta come copertina'),
                  subtitle: isCover ? const Text('È già la copertina attuale') : null,
                  enabled: !isCover && !busy,
                  onTap: !isCover && !busy
                      ? () {
                          Navigator.of(ctx).pop();
                          _setAsCover(photo);
                        }
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: cs.error),
                  title: const Text('Elimina foto'),
                  enabled: !busy,
                  onTap: !busy
                      ? () {
                          Navigator.of(ctx).pop();
                          _deletePhoto(photo);
                        }
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HeaderCard({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.photo_library_outlined, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final bool isCover;
  final bool busy;
  final VoidCallback onMenu;

  const _PhotoTile({
    required this.url,
    required this.isCover,
    required this.busy,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onMenu,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  url,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

              // overlay “soft” per migliorare leggibilità badge
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.35),
                        Colors.transparent,
                        Colors.black.withOpacity(0.20),
                      ],
                    ),
                  ),
                ),
              ),

              if (isCover)
                Positioned(
                  left: 10,
                  top: 10,
                  child: _CoverChip(),
                ),

              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                ),
              ),

              if (busy)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'COPERTINA',
        style: tt.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onAdd;
  final bool uploading;

  const _EmptyState({
    required this.onAdd,
    required this.uploading,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.add_photo_alternate_outlined, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text(
              'Aggiungi le foto del tuo locale',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Carica almeno una foto. La prima diventerà automaticamente copertina.',
              style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
              label: Text(uploading ? 'Caricamento…' : 'Carica una foto'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
