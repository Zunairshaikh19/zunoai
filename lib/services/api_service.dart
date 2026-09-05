import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  final String apiKey;
  static const String _imgBBKey = "d06e36c9de1d91a12a0c824e8c8837e4";

  ApiService(this.apiKey);

  Future<String?> generateImage({
    required String prompt,
    required File referenceImage,
  }) async {
    // Model candidates in order
    final models = [
      'imagen-3.0-generate-002',
      'imagen-3.0-fast-generate-001',
      'imagen-3.0-generate-001',
    ];

    for (final model in models) {
      // Try :generateImages method
      String? result = await _tryGenerateImages(model, prompt);
      if (result != null) return result;

      // Try :predict method
      result = await _tryPredict(model, prompt);
      if (result != null) return result;
    }

    // Log available models for debugging
    await _listAvailableModels();

    return null;
  }

  Future<String?> _tryGenerateImages(String model, String prompt) async {
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateImages?key=$apiKey',
      );

      final body = jsonEncode({
        "prompt": prompt,
        "config": {
          "numberOfImages": 1,
          "aspectRatio": "1:1",
          "outputMimeType": "image/jpeg"
        }
      });

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? base64Image;
        if (data['generatedImages'] != null && (data['generatedImages'] as List).isNotEmpty) {
          base64Image = data['generatedImages'][0]['image']['imageBytes'];
        } else if (data['predictions'] != null && (data['predictions'] as List).isNotEmpty) {
          base64Image = data['predictions'][0]['bytesBase64Encoded'];
        }

        if (base64Image != null && base64Image.isNotEmpty) {
          return await _uploadBase64ToImgBB(base64Image);
        }
      } else {
        print("Model $model (:generateImages) -> Status ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("Model $model (:generateImages) Exception: $e");
    }
    return null;
  }

  Future<String?> _tryPredict(String model, String prompt) async {
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:predict?key=$apiKey',
      );

      final body = jsonEncode({
        "instances": [
          {"prompt": prompt}
        ],
        "parameters": {
          "sampleCount": 1,
          "aspectRatio": "1:1",
          "outputMimeType": "image/jpeg"
        }
      });

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['predictions'] != null && (data['predictions'] as List).isNotEmpty) {
          final String base64Image = data['predictions'][0]['bytesBase64Encoded'];
          return await _uploadBase64ToImgBB(base64Image);
        }
      } else {
        print("Model $model (:predict) -> Status ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("Model $model (:predict) Exception: $e");
    }
    return null;
  }

  Future<void> _listAvailableModels() async {
    try {
      final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("=== AVAILABLE MODELS FOR THIS API KEY ===");
        if (data['models'] != null) {
          for (var m in data['models']) {
            print("Model: ${m['name']} | Methods: ${m['supportedGenerationMethods']}");
          }
        }
      } else {
        print("ListModels Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("ListModels Exception: $e");
    }
  }

  Future<String?> _uploadBase64ToImgBB(String base64Image) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload?key=$_imgBBKey'),
        body: {'image': base64Image},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['data']['url'];
      } else {
        print("ImgBB Upload Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("ImgBB Upload Exception: $e");
    }
    return null;
  }
}
