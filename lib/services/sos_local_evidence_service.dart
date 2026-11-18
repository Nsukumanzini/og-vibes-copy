import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _latestSosPacketKey = 'sos_local_evidence_latest_v1';

class SosCaptureOptions {
  const SosCaptureOptions({
    this.includeLocation = true,
    this.includePhotos = true,
    this.includeAudio = false,
  });

  final bool includeLocation;
  final bool includePhotos;
  final bool includeAudio;
}

class SosCaptureProgress {
  const SosCaptureProgress(this.label, this.value);

  final String label;
  final double value;
}

class SosLocalEvidencePacket {
  const SosLocalEvidencePacket({
    required this.serviceName,
    required this.createdAt,
    required this.location,
    required this.photos,
    required this.audio,
    required this.issues,
    required this.saved,
    this.saveError,
  });

  final String serviceName;
  final DateTime createdAt;
  final Position? location;
  final Map<CameraLensDirection, Uint8List> photos;
  final Uint8List? audio;
  final List<String> issues;
  final bool saved;
  final String? saveError;

  String get savedSummary {
    final parts = <String>[];
    if (location != null) parts.add('location');
    if (photos.containsKey(CameraLensDirection.back)) {
      parts.add('rear photo');
    }
    if (photos.containsKey(CameraLensDirection.front)) {
      parts.add('front photo');
    }
    if (audio != null) parts.add('10-second audio');
    return parts.isEmpty ? 'No evidence captured' : parts.join(' · ');
  }
}

/// Device-only SOS evidence storage. A new packet replaces the previous one.
class SosLocalEvidenceService {
  const SosLocalEvidenceService();

  Future<SosLocalEvidencePacket> capture({
    required String serviceName,
    required SosCaptureOptions options,
    required ValueChanged<SosCaptureProgress> onProgress,
  }) async {
    final createdAt = DateTime.now();
    final issues = <String>[];
    Position? location;
    final photos = <CameraLensDirection, Uint8List>{};
    Uint8List? audio;
    var step = 0;
    final plannedSteps =
        (options.includeLocation ? 1 : 0) +
        (options.includePhotos ? 2 : 0) +
        (options.includeAudio ? 1 : 0);
    void progress(String label) {
      step++;
      onProgress(
        SosCaptureProgress(
          label,
          plannedSteps == 0 ? 0.9 : (step / plannedSteps).clamp(0.0, 0.9),
        ),
      );
    }

    if (options.includeLocation) {
      progress('Getting your current location…');
      try {
        location = await _getLocation();
        if (location == null) issues.add('Location was not available.');
      } catch (_) {
        issues.add('Location was not available.');
      }
    }

    if (options.includePhotos) {
      for (final direction in <CameraLensDirection>[
        CameraLensDirection.back,
        CameraLensDirection.front,
      ]) {
        progress(
          direction == CameraLensDirection.back
              ? 'Taking rear-camera photo…'
              : 'Taking front-camera photo…',
        );
        try {
          final bytes = await _takePhoto(direction);
          if (bytes != null) photos[direction] = bytes;
        } catch (_) {
          issues.add(
            direction == CameraLensDirection.back
                ? 'Rear-camera photo was not available.'
                : 'Front-camera photo was not available.',
          );
        }
      }
    }

    if (options.includeAudio) {
      progress('Recording 10 seconds of audio…');
      try {
        audio = await _recordTenSeconds(onProgress: onProgress);
        if (audio == null) issues.add('Audio recording was not available.');
      } catch (_) {
        issues.add('Audio recording was not available.');
      }
    }

    onProgress(const SosCaptureProgress('Saving on this device…', 0.96));
    try {
      final preferences = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'service': serviceName,
        'created_at': createdAt.toIso8601String(),
        if (location != null)
          'location': <String, dynamic>{
            'latitude': location.latitude,
            'longitude': location.longitude,
            'accuracy_meters': location.accuracy,
          },
        'photos': <String, String>{
          for (final entry in photos.entries)
            entry.key.name: base64Encode(entry.value),
        },
        if (audio != null) 'audio_wav': base64Encode(audio),
        'issues': issues,
      };
      final saved = await preferences.setString(
        _latestSosPacketKey,
        jsonEncode(payload),
      );
      if (!saved) throw StateError('Device storage declined the SOS packet.');
      onProgress(const SosCaptureProgress('Saved on this device', 1));
      return SosLocalEvidencePacket(
        serviceName: serviceName,
        createdAt: createdAt,
        location: location,
        photos: photos,
        audio: audio,
        issues: issues,
        saved: true,
      );
    } catch (error) {
      return SosLocalEvidencePacket(
        serviceName: serviceName,
        createdAt: createdAt,
        location: location,
        photos: photos,
        audio: audio,
        issues: issues,
        saved: false,
        saveError: error.toString(),
      );
    }
  }

  Future<void> deleteLatest() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_latestSosPacketKey);
  }

  Future<Position?> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }

  Future<Uint8List?> _takePhoto(CameraLensDirection direction) async {
    final cameras = await availableCameras();
    CameraDescription? camera;
    for (final candidate in cameras) {
      if (candidate.lensDirection == direction) {
        camera = candidate;
        break;
      }
    }
    if (camera == null) return null;

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      final image = await controller.takePicture();
      return await image.readAsBytes();
    } finally {
      await controller.dispose();
    }
  }

  Future<Uint8List?> _recordTenSeconds({
    required ValueChanged<SosCaptureProgress> onProgress,
  }) async {
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) return null;
      final chunks = <Uint8List>[];
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      final subscription = stream.listen(chunks.add);
      try {
        for (var remaining = 10; remaining > 0; remaining--) {
          onProgress(
            SosCaptureProgress(
              'Recording audio… ${remaining}s remaining',
              (10 - remaining) / 10,
            ),
          );
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } finally {
        await recorder.stop();
        await subscription.cancel();
      }
      final pcm = Uint8List.fromList(chunks.expand((chunk) => chunk).toList());
      return pcm.isEmpty ? null : _wavFromPcm(pcm);
    } finally {
      await recorder.dispose();
    }
  }

  Uint8List _wavFromPcm(Uint8List pcm) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    final header = ByteData(44);
    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(
      28,
      sampleRate * channels * bitsPerSample ~/ 8,
      Endian.little,
    );
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList(<int>[...header.buffer.asUint8List(), ...pcm]);
  }
}
