import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraPreviewWidget extends StatelessWidget {
  final CameraController controller;

  const CameraPreviewWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final aspectRatio = controller.value.aspectRatio;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final previewAspectRatio = aspectRatio;

        // Calculate the size that fits within constraints while maintaining aspect ratio
        double widgetWidth = width;
        double widgetHeight = width / previewAspectRatio;

        // If height exceeds constraints, scale down
        if (widgetHeight > height) {
          widgetHeight = height;
          widgetWidth = height * previewAspectRatio;
        }

        return Center(
          child: SizedBox(
            width: widgetWidth,
            height: widgetHeight,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? width,
                height: controller.value.previewSize?.width ?? height,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}
