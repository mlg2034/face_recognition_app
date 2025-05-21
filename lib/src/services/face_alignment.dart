import 'dart:math';
import 'dart:math' as math;
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class FaceAlignment {
  // Стандартные координаты для глаз в выходном изображении 112x112
  static final List<Point<double>> REFERENCE_FACIAL_POINTS = [
    Point(38.2946, 51.6963), // левый глаз
    Point(73.5318, 51.5014), // правый глаз
    Point(56.0252, 71.7366), // нос
    Point(41.5493, 92.3655), // левый угол рта
    Point(70.7299, 92.2041)  // правый угол рта
  ];
  
  static final int OUTPUT_SIZE = 112; // Стандартный размер для MobileFaceNet/ArcFace

  /// Выравнивает лицо по ключевым точкам с использованием аффинного преобразования
  static img.Image alignFace(img.Image image, Face face) {
    try {
      // Получаем расширенный набор ключевых точек лица
      final points = _getEnhancedKeyPoints(face);
      
      // Если не удалось получить нужные точки, возвращаем исходное изображение с ресайзом
      if (points.length < 2) {
        print('Warning: Not enough facial landmarks for proper alignment');
        return _cropAndResizeFace(image, face.boundingBox);
      }
      
      // Создаем матрицу преобразования (масштабирование + поворот + перенос)
      final transformation = _computeAffineTransform(points, 
                                                   REFERENCE_FACIAL_POINTS, 
                                                   true);
      
      if (transformation == null) {
        print('Warning: Could not compute affine transformation for face alignment');
        return _cropAndResizeFace(image, face.boundingBox);
      }
      
      // Проверка качества результата - если результат выглядит неправдоподобным, используем оригинал
      if (transformation.any((value) => value.isNaN || value.isInfinite)) {
        print('Warning: Invalid transformation values detected');
        return _cropAndResizeFace(image, face.boundingBox);
      }
      
      // Применяем аффинное преобразование к изображению
      final transformedImage = _applyAffineTransform(image, transformation);
      
      // Проверка качества результата - если результат выглядит неправдоподобным, используем оригинал
      if (transformedImage.width != OUTPUT_SIZE || transformedImage.height != OUTPUT_SIZE) {
        print('Warning: Transformation resulted in invalid image size');
        return _cropAndResizeFace(image, face.boundingBox);
      }
      
      return transformedImage;
    } catch (e) {
      print('Error in face alignment: $e');
      // В случае ошибки просто изменяем размер исходного изображения
      return _cropAndResizeFace(image, face.boundingBox);
    }
  }

  /// Извлекает расширенный набор ключевых точек лица из объекта Face
  static List<Point<double>> _getEnhancedKeyPoints(Face face) {
    final List<Point<double>> points = [];
    
    // Extract standard 5 points
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    final nose = face.landmarks[FaceLandmarkType.noseBase];
    final leftMouth = face.landmarks[FaceLandmarkType.leftMouth];
    final rightMouth = face.landmarks[FaceLandmarkType.rightMouth];
    
    // If we have the essential eye landmarks, prioritize those as they're most important
    bool hasEyes = leftEye != null && rightEye != null;
    
    if (leftEye != null) points.add(Point<double>(leftEye.position.x.toDouble(), leftEye.position.y.toDouble()));
    if (rightEye != null) points.add(Point<double>(rightEye.position.x.toDouble(), rightEye.position.y.toDouble()));
    if (nose != null) points.add(Point<double>(nose.position.x.toDouble(), nose.position.y.toDouble()));
    if (leftMouth != null) points.add(Point<double>(leftMouth.position.x.toDouble(), leftMouth.position.y.toDouble()));
    if (rightMouth != null) points.add(Point<double>(rightMouth.position.x.toDouble(), rightMouth.position.y.toDouble()));
    
    // If we don't have enough standard landmarks, try to use contours
    if (points.length < 2) {
      try {
        final leftEyeContour = face.contours[FaceContourType.leftEye];
        final rightEyeContour = face.contours[FaceContourType.rightEye];
        
        if (leftEyeContour != null && leftEyeContour.points.isNotEmpty) {
          // Find center of eye
          double sumX = 0, sumY = 0;
          for (final point in leftEyeContour.points) {
            sumX += point.x;
            sumY += point.y;
          }
          Point<double> leftEyeCenter = Point<double>(
            sumX / leftEyeContour.points.length,
            sumY / leftEyeContour.points.length
          );
          points.add(leftEyeCenter);
        }
        
        if (rightEyeContour != null && rightEyeContour.points.isNotEmpty) {
          // Find center of eye
          double sumX = 0, sumY = 0;
          for (final point in rightEyeContour.points) {
            sumX += point.x;
            sumY += point.y;
          }
          Point<double> rightEyeCenter = Point<double>(
            sumX / rightEyeContour.points.length,
            sumY / rightEyeContour.points.length
          );
          points.add(rightEyeCenter);
        }
      } catch (e) {
        print('Error extracting eye contours: $e');
      }
    }
    
    // Only add contour points if we have the essential eye landmarks
    if (hasEyes) {
      try {
        // Add face contour points for better alignment
        final faceContour = face.contours[FaceContourType.face];
        if (faceContour != null && faceContour.points.isNotEmpty) {
          // Add key points from the contour (forehead, chin, etc.)
          final step = faceContour.points.length ~/ 4;
          for (int i = 0; i < faceContour.points.length; i += step) {
            final point = faceContour.points[i];
            points.add(Point<double>(point.x.toDouble(), point.y.toDouble()));
          }
        }
      } catch (e) {
        print('Error extracting face contours: $e');
      }
    }
    
    return points;
  }

  /// Вычисляет матрицу аффинного преобразования
  static List<double>? _computeAffineTransform(
      List<Point<double>> fromPoints, 
      List<Point<double>> toPoints,
      bool fullAffine) {
    if (fromPoints.length != toPoints.length || fromPoints.length < 3) {
      return null;
    }
    
    // Используем метод наименьших квадратов для нахождения матрицы преобразования
    // Реализация решения системы линейных уравнений для нахождения параметров
    // аффинного преобразования (a, b, c, d, e, f)
    double a = 0, b = 0, c = 0, d = 0, e = 0, f = 0;
    
    if (fromPoints.length == 2) {
      // Простое выравнивание по двум точкам (обычно глаза)
      final dx = toPoints[1].x - toPoints[0].x;
      final dy = toPoints[1].y - toPoints[0].y;
      final scale = sqrt(dx * dx + dy * dy) / 
                   sqrt(pow(fromPoints[1].x - fromPoints[0].x, 2) + 
                        pow(fromPoints[1].y - fromPoints[0].y, 2));
      
      final angle = atan2(dy, dx) - 
                   atan2(fromPoints[1].y - fromPoints[0].y, 
                         fromPoints[1].x - fromPoints[0].x);
      
      a = cos(angle) * scale;
      b = sin(angle) * scale;
      c = toPoints[0].x - (a * fromPoints[0].x + b * fromPoints[0].y);
      d = -b;
      e = a;
      f = toPoints[0].y - (d * fromPoints[0].x + e * fromPoints[0].y);
    } else {
      // Упрощенное решение для более 2-х точек
      double meanSrcX = 0, meanSrcY = 0, meanDstX = 0, meanDstY = 0;
      
      // Вычисляем средние значения
      for (int i = 0; i < fromPoints.length; i++) {
        meanSrcX += fromPoints[i].x;
        meanSrcY += fromPoints[i].y;
        meanDstX += toPoints[i].x;
        meanDstY += toPoints[i].y;
      }
      
      meanSrcX /= fromPoints.length;
      meanSrcY /= fromPoints.length;
      meanDstX /= toPoints.length;
      meanDstY /= toPoints.length;
      
      // Центрируем точки
      final List<Point<double>> srcCentered = fromPoints.map(
        (p) => Point<double>(p.x - meanSrcX, p.y - meanSrcY)
      ).toList();
      
      final List<Point<double>> dstCentered = toPoints.map(
        (p) => Point<double>(p.x - meanDstX, p.y - meanDstY)
      ).toList();
      
      // Вычисляем параметры преобразования
      double sumSrcX2 = 0, sumSrcY2 = 0, sumSrcXY = 0;
      double sumSrcXDstX = 0, sumSrcYDstX = 0, sumSrcXDstY = 0, sumSrcYDstY = 0;
      
      for (int i = 0; i < srcCentered.length; i++) {
        final srcX = srcCentered[i].x;
        final srcY = srcCentered[i].y;
        final dstX = dstCentered[i].x;
        final dstY = dstCentered[i].y;
        
        sumSrcX2 += srcX * srcX;
        sumSrcY2 += srcY * srcY;
        sumSrcXY += srcX * srcY;
        sumSrcXDstX += srcX * dstX;
        sumSrcYDstX += srcY * dstX;
        sumSrcXDstY += srcX * dstY;
        sumSrcYDstY += srcY * dstY;
      }
      
      double det = sumSrcX2 * sumSrcY2 - sumSrcXY * sumSrcXY;
      
      if (det != 0) {
        a = (sumSrcXDstX * sumSrcY2 - sumSrcXY * sumSrcYDstX) / det;
        b = (sumSrcX2 * sumSrcYDstX - sumSrcXY * sumSrcXDstX) / det;
        d = (sumSrcXDstY * sumSrcY2 - sumSrcXY * sumSrcYDstY) / det;
        e = (sumSrcX2 * sumSrcYDstY - sumSrcXY * sumSrcXDstY) / det;
        
        c = meanDstX - a * meanSrcX - b * meanSrcY;
        f = meanDstY - d * meanSrcX - e * meanSrcY;
      }
    }
    
    return [a, b, c, d, e, f];
  }

  /// Применяет аффинное преобразование к изображению
  static img.Image _applyAffineTransform(img.Image srcImage, List<double> transform) {
    final a = transform[0];
    final b = transform[1];
    final c = transform[2];
    final d = transform[3];
    final e = transform[4];
    final f = transform[5];
    
    final outputImage = img.Image(width: OUTPUT_SIZE, height: OUTPUT_SIZE);
    
    for (int y = 0; y < OUTPUT_SIZE; y++) {
      for (int x = 0; x < OUTPUT_SIZE; x++) {
        // Обратное отображение координат из выходного изображения в исходное
        final sourceX = a * x + b * y + e;
        final sourceY = c * x + d * y + f;
        
        // Билинейная интерполяция
        if (sourceX >= 0 && sourceY >= 0 && 
            sourceX < srcImage.width - 1 && sourceY < srcImage.height - 1) {
          final x0 = sourceX.floor();
          final y0 = sourceY.floor();
          final x1 = x0 + 1;
          final y1 = y0 + 1;
          
          final dx = sourceX - x0;
          final dy = sourceY - y0;
          
          // Получаем цвета соседних пикселей
          final pixel00 = srcImage.getPixel(x0, y0);
          final pixel01 = srcImage.getPixel(x0, y1);
          final pixel10 = srcImage.getPixel(x1, y0);
          final pixel11 = srcImage.getPixel(x1, y1);
          
          // Интерполируем по каждому каналу
          final r = _interpolate(
            pixel00.r.toInt(), 
            pixel10.r.toInt(), 
            pixel01.r.toInt(), 
            pixel11.r.toInt(), 
            dx, dy);
          
          final g = _interpolate(
            pixel00.g.toInt(), 
            pixel10.g.toInt(), 
            pixel01.g.toInt(), 
            pixel11.g.toInt(), 
            dx, dy);
          
          final b = _interpolate(
            pixel00.b.toInt(), 
            pixel10.b.toInt(), 
            pixel01.b.toInt(), 
            pixel11.b.toInt(), 
            dx, dy);
          
          outputImage.setPixelRgb(x, y, r, g, b);
        }
      }
    }
    
    return outputImage;
  }

  /// Функция билинейной интерполяции для одного канала
  static int _interpolate(int c00, int c10, int c01, int c11, double dx, double dy) {
    final a = c00 * (1 - dx) * (1 - dy);
    final b = c10 * dx * (1 - dy);
    final c = c01 * (1 - dx) * dy;
    final d = c11 * dx * dy;
    return (a + b + c + d).round();
  }
  
  static img.Image _resizeImage(img.Image image, int targetWidth, int targetHeight) {
    // Ensure square output by cropping to square first
    final squareSize = math.min(image.width, image.height);
    final x = (image.width - squareSize) ~/ 2;
    final y = (image.height - squareSize) ~/ 2;
    
    final cropped = img.copyCrop(
      image,
      x: x,
      y: y,
      width: squareSize,
      height: squareSize
    );
    
    return img.copyResize(
      cropped,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic
    );
  }

  /// Crop and resize face based on bounding box as a fallback
  static img.Image _cropAndResizeFace(img.Image image, Rect boundingBox) {
    try {
      // Add padding around face
      final centerX = boundingBox.left + boundingBox.width / 2;
      final centerY = boundingBox.top + boundingBox.height / 2;
      final size = math.max(boundingBox.width, boundingBox.height) * 1.4; // Add 40% padding
      
      // Calculate crop bounds
      final cropLeft = (centerX - size / 2).round();
      final cropTop = (centerY - size / 2).round();
      final cropSize = size.round();
      
      // Ensure crop bounds are within image
      final safeLeft = math.max(0, math.min(image.width - 1, cropLeft));
      final safeTop = math.max(0, math.min(image.height - 1, cropTop));
      final safeWidth = math.min(image.width - safeLeft, cropSize);
      final safeHeight = math.min(image.height - safeTop, cropSize);
      
      // Crop and resize
      if (safeWidth > 0 && safeHeight > 0) {
        final croppedImage = img.copyCrop(
          image,
          x: safeLeft,
          y: safeTop,
          width: safeWidth,
          height: safeHeight
        );
        
        return img.copyResize(
          croppedImage,
          width: OUTPUT_SIZE,
          height: OUTPUT_SIZE,
          interpolation: img.Interpolation.cubic
        );
      }
    } catch (e) {
      print('Error in crop and resize: $e');
    }
    
    // Last resort fallback - just resize the whole image
    return _resizeImage(image, OUTPUT_SIZE, OUTPUT_SIZE);
  }
} 