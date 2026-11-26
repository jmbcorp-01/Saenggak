import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../core/photo_prep.dart';
import '../data/app_state.dart';
import '../theme/tokens.dart';

/// Takes the profile photo with the camera. There is deliberately no way to
/// pick a file or a gallery image: the photo has to be taken here, of a real
/// face, and the server then checks there is exactly one clear face in it.
class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key, required this.state, this.cameras});

  final AppState state;

  /// Overrides the device's cameras, for tests.
  final Future<List<CameraDescription>> Function()? cameras;

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  Uint8List? _taken;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // The camera is let go while the app is in the background and taken again on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c.dispose();
    } else if (state == AppLifecycleState.resumed && _taken == null) {
      _open();
    }
  }

  Future<void> _open() async {
    try {
      final cameras = await (widget.cameras ?? availableCameras)();
      if (cameras.isEmpty) {
        setState(() => _error = '이 기기에서 카메라를 찾지 못했어요. 카메라가 있는 기기에서 사진을 찍어주세요.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.code.contains('ccess') || e.code.contains('ermission')
            ? '카메라 권한이 필요해요. 설정에서 카메라 사용을 허용한 뒤 다시 열어주세요.'
            : '카메라를 열지 못했어요. 다시 시도해주세요.',
      );
    }
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final prepared = preparePhoto(
        await file.readAsBytes(),
        // The web camera already mirrors front-camera pictures to match the preview.
        mirror: !kIsWeb && _camera?.lensDirection == CameraLensDirection.front,
      );
      if (!mounted) return;
      setState(() {
        _taken = prepared;
        _error = prepared == null ? photoProblemMessage('bad_image') : null;
      });
    } on CameraException {
      if (mounted) setState(() => _error = '사진을 찍지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _use() async {
    final photo = _taken;
    if (photo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.setPhoto(photo);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = photoProblemMessage(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = photoProblemMessage('unknown'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retake() => setState(() {
    _taken = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final Widget view;
    if (_taken != null) {
      view = Image.memory(_taken!, fit: BoxFit.cover, semanticLabel: '방금 찍은 사진');
    } else if (ready) {
      view = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // previewSize is landscape; the preview is shown upright.
          width: c.value.previewSize?.height ?? 1,
          height: c.value.previewSize?.width ?? 1,
          child: CameraPreview(c),
        ),
      );
    } else {
      view = ColoredBox(color: SgColors.band);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('프로필 사진 찍기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              '생각은 사람이 직접 쓰는 곳이라, 프로필 사진도 지금 카메라로 찍은 본인 얼굴만 쓸 수 있어요. 앨범 사진이나 그림, AI 이미지는 올릴 수 없어요.',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox.square(dimension: 260, child: ClipOval(child: view)),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SgColors.accentText, fontSize: 14, height: 1.4),
                ),
              )
            else
              Text(
                _taken == null ? '밝은 곳에서 얼굴이 원 안에 오도록 정면을 봐주세요.' : '이 사진으로 할까요?',
                textAlign: TextAlign.center,
                style: SgText.small,
              ),
            const SizedBox(height: 24),
            if (_taken == null)
              Center(
                child: Semantics(
                  button: true,
                  label: '사진 찍기',
                  child: InkResponse(
                    onTap: ready && !_busy ? _shoot : null,
                    radius: 40,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ready ? SgColors.ink : SgColors.outline, width: 4),
                      ),
                      padding: const EdgeInsets.all(5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ready && !_busy ? SgColors.ink : SgColors.outline,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _retake,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      child: const Text('다시 찍기'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _use,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('이 사진 쓰기'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
