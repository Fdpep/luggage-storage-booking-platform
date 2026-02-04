import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
//
import 'package:BagDrop/models/partner.dart';
import 'package:BagDrop/models/partner_photo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_repo.dart';
import 'package:BagDrop/services/supabase/partner_photo/partner_photo_storage.dart';

class PartnerPhotosScreen extends StatefulWidget {
  final Partner partner;

  const PartnerPhotosScreen({super.key, required this.partner});

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

      // ✅ UI coerente: copertina sempre in cima
      final normalized = List<PartnerPhoto>.from(photos);
      final coverIdx = normalized.indexWhere((p) => p.isCover);
      if (coverIdx > 0) {
        final cover = normalized.removeAt(coverIdx);
        normalized.insert(0, cover);
      }

      if (!mounted) return;
      setState(() {
        _photos = normalized;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Foto caricata.')));
    } catch (e, st) {
      debugPrint('Errore _addPhoto: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante il caricamento della foto.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// ✅ Salva ordine + copertina su DB:
  /// - index 0 => isCover=true, sortOrder=0
  /// - others  => isCover=false, sortOrder=i
  Future<void> _saveOrderToDb(
    List<PartnerPhoto> ordered, {
    String? forceCoverId,
  }) async {
    final temp = List<PartnerPhoto>.from(ordered);

    // ✅ Se sto impostando una nuova copertina, FORZO quella foto in cima
    if (forceCoverId != null) {
      final idx = temp.indexWhere((p) => p.id == forceCoverId);
      if (idx > 0) {
        final forced = temp.removeAt(idx);
        temp.insert(0, forced);
      }
    } else {
      // ✅ Caso riordino normale: mantieni la cover attuale in cima
      final coverIdx = temp.indexWhere((p) => p.isCover);
      if (coverIdx > 0) {
        final cover = temp.removeAt(coverIdx);
        temp.insert(0, cover);
      }
    }

    for (var i = 0; i < temp.length; i++) {
      final p = temp[i];
      final isCover = (forceCoverId != null)
          ? (p.id == forceCoverId)
          : (i == 0);

      await _photoRepo.updatePhoto(
        photoId: p.id,
        isCover: isCover,
        sortOrder: i,
      );
    }

    await _loadPhotos();
  }

  Future<void> _setAsCover(PartnerPhoto photo) async {
    if (_savingCoverId != null) return;

    setState(() => _savingCoverId = photo.id);

    try {
      // ✅ richiesto: nuova copertina va in prima posizione
      final reordered = <PartnerPhoto>[
        photo,
        ..._photos.where((p) => p.id != photo.id),
      ];

      await _saveOrderToDb(reordered, forceCoverId: photo.id);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copertina aggiornata.')));
    } catch (e, st) {
      debugPrint('Errore _setAsCover: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante l’aggiornamento della copertina.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingCoverId = null);
    }
  }

  Future<void> _deletePhoto(PartnerPhoto photo) async {
    if (_deletingId != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Elimina foto'),
          content: const Text(
            'Vuoi davvero eliminare questa foto dal tuo profilo attività?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Annulla',
                style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Elimina',
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _deletingId = photo.id);

    try {
      await _photoRepo.deletePhoto(photo.id);
      await _loadPhotos();

      // Se era copertina e restano foto, promuovi la prima
      if (photo.isCover &&
          _photos.isNotEmpty &&
          !_photos.any((p) => p.isCover)) {
        await _setAsCover(_photos.first);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Foto eliminata.')));
    } catch (e, st) {
      debugPrint('Errore _deletePhoto: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Errore durante l’eliminazione della foto.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _openReorderSheet() {
    if (_photos.length < 2) return;

    final initial = List<PartnerPhoto>.from(_photos);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;

        var temp = List<PartnerPhoto>.from(initial);
        bool saving = false;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> doSave() async {
              if (saving) return;
              setModalState(() => saving = true);

              try {
                await _saveOrderToDb(temp);

                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ordine aggiornato.')),
                );
              } catch (e, st) {
                debugPrint('Errore doSave reorder: $e\n$st');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Errore durante il salvataggio dell’ordine.'),
                  ),
                );
              } finally {
                if (mounted) setModalState(() => saving = false);
              }
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Riordina foto',
                      style: tt.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Trascina le righe per cambiare l’ordine. La copertina resta sempre in cima.',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ✅ FIX CRITICO: ReorderableListView deve stare in uno spazio "bounded"
                    // Non dentro iosSection (che usa Column mainAxisSize min).
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.35),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: ReorderableListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            buildDefaultDragHandles: false,
                            itemCount: temp.length,
                            onReorder: saving
                                ? (_, __) {}
                                : (oldIndex, newIndex) {
                                    // Copertina (index 0) non si muove
                                    if (oldIndex == 0) return;

                                    // Non consentire inserimento in posizione 0
                                    if (newIndex == 0) newIndex = 1;

                                    if (newIndex > oldIndex) newIndex -= 1;

                                    setModalState(() {
                                      final item = temp.removeAt(oldIndex);
                                      temp.insert(newIndex, item);
                                    });
                                  },
                            itemBuilder: (ctx, index) {
                              final p = temp[index];
                              final isCover = index == 0;

                              final row = _ReorderRow(
                                url: p.url,
                                title: isCover
                                    ? 'Copertina'
                                    : 'Foto ${index + 1}',
                                subtitle: isCover
                                    ? 'Resta sempre in cima'
                                    : 'Trascina per riordinare',
                                isCover: isCover,
                                enabled: !saving,
                              );

                              // ✅ UX: trascinamento immediato (no long-press)
                              if (isCover) {
                                return KeyedSubtree(
                                  key: ValueKey(p.id),
                                  child: row,
                                );
                              }

                              return ReorderableDragStartListener(
                                key: ValueKey(p.id),
                                index: index,
                                child: row,
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Annulla'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: saving ? null : doSave,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Salva'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final busyGlobal = _savingCoverId != null || _deletingId != null;

    return Scaffold(
      appBar: AppBar(
        // ✅ come ProfiloPage: primary + titolo centrale
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Foto del locale',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (tt.titleMedium ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onPrimary, // ✅ forza bianco (o comunque onPrimary)
          ),
        ),

        actions: [
          if (!_loading && _error == null && _photos.length > 1)
            IconButton(
              tooltip: 'Riordina',
              onPressed: busyGlobal ? null : _openReorderSheet,
              icon: const Icon(Icons.swap_vert),
            ),
        ],
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
                iosSection(
                  context,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: cs.surfaceVariant.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: cs.outlineVariant.withOpacity(0.35),
                              ),
                            ),
                            child: Icon(
                              Icons.photo_library_outlined,
                              color: cs.onSurface.withOpacity(0.75),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.partner.name,
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _photos.isEmpty
                                      ? 'Nessuna foto caricata'
                                      : '${_photos.length} foto • Tocca una foto per le opzioni',
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_photos.length > 1) ...[
                      thinDivider(context),
                      InkWell(
                        onTap: busyGlobal ? null : _openReorderSheet,
                        splashColor: cs.onSurface.withOpacity(0.06),
                        highlightColor: cs.onSurface.withOpacity(0.03),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.swap_vert,
                                size: 20,
                                color: cs.onSurface.withOpacity(0.75),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Riordina foto',
                                      style: tt.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Trascina e salva l’ordine in un tap',
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: cs.onSurface.withOpacity(0.35),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                if (_photos.isEmpty)
                  _EmptyState(
                    onAdd: _uploading ? null : _addPhoto,
                    uploading: _uploading,
                  )
                else
                  iosSection(
                    context,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
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
                                _savingCoverId == photo.id ||
                                _deletingId == photo.id;

                            return _PhotoTile(
                              url: photo.url,
                              isCover: isCover,
                              busy: busy,
                              onMenu: () => _openActionsSheet(photo),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),

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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Azioni foto',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                iosSection(
                  ctx,
                  children: [
                    _SheetRow(
                      icon: Icons.star_outline,
                      title: 'Imposta come copertina',
                      subtitle: isCover
                          ? 'È già la copertina attuale'
                          : 'Diventerà la prima foto',
                      enabled: !isCover && !busy,
                      iconColor: cs.primary,
                      onTap: !isCover && !busy
                          ? () {
                              Navigator.of(ctx).pop();
                              _setAsCover(photo);
                            }
                          : null,
                    ),
                    thinDivider(ctx),
                    _SheetRow(
                      icon: Icons.delete_outline,
                      title: 'Elimina foto',
                      subtitle: 'Rimuove la foto dal profilo',
                      enabled: !busy,
                      iconColor: cs.error,
                      onTap: !busy
                          ? () {
                              Navigator.of(ctx).pop();
                              _deletePhoto(photo);
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
        splashColor: Colors.black.withOpacity(0.06),
        highlightColor: Colors.black.withOpacity(0.03),
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
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.28),
                        Colors.transparent,
                        Colors.black.withOpacity(0.18),
                      ],
                    ),
                  ),
                ),
              ),
              if (isCover)
                const Positioned(left: 10, top: 10, child: _CoverChip()),
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
                  child: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 18,
                  ),
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
  const _CoverChip();

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

  const _EmptyState({required this.onAdd, required this.uploading});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return iosSection(
      context,
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Icon(
                  Icons.add_photo_alternate_outlined,
                  color: cs.onSurface.withOpacity(0.75),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Aggiungi le foto del tuo locale',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Carica almeno una foto. La prima diventerà automaticamente copertina.',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.7),
                ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final Color iconColor;
  final VoidCallback? onTap;

  const _SheetRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.enabled,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: enabled ? onTap : null,
      splashColor: cs.onSurface.withOpacity(0.06),
      highlightColor: cs.onSurface.withOpacity(0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: enabled ? iconColor : cs.onSurface.withOpacity(0.25),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: enabled
                          ? cs.onSurface
                          : cs.onSurface.withOpacity(0.45),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.65),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: cs.onSurface.withOpacity(enabled ? 0.35 : 0.20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderRow extends StatelessWidget {
  final String url;
  final String title;
  final String subtitle;
  final bool isCover;
  final bool enabled;

  const _ReorderRow({
    required this.url,
    required this.title,
    required this.subtitle,
    required this.isCover,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCover)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceVariant.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: cs.outlineVariant.withOpacity(0.35),
                              ),
                            ),
                            child: Text(
                              'Copertina',
                              style: tt.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface.withOpacity(0.75),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Opacity(
                opacity: enabled && !isCover ? 1 : 0.35,
                child: Icon(
                  Icons.drag_handle,
                  color: cs.onSurface.withOpacity(0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS Section Container
Widget iosSection(BuildContext context, {required List<Widget> children}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    decoration: BoxDecoration(
      color: cs.surfaceVariant.withOpacity(0.25),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

Widget thinDivider(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Divider(
    height: 1,
    thickness: 1,
    color: cs.outlineVariant.withOpacity(0.7),
  );
}
