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
    // Models with generateContent for image generation from user's API key
    final imageModels = [
      'gemini-2.5-flash-image',
      'gemini-3.1-flash-image',
      'gemini-3-pro-image',
    ];

    for (final model in imageModels) {
      String? result = await _tryGenerateContent(model, prompt);
      if (result != null) return result;
    }

    // Fallback to Imagen 3 if available
    final imagenModels = [
      'imagen-3.0-generate-002',
      'imagen-3.0-fast-generate-001',
    ];

    for (final model in imagenModels) {
      String? result = await _tryGenerateImages(model, prompt);
      if (result != null) return result;
    }

    return null;
  }

  Future<String?> _tryGenerateContent(String model, String prompt) async {
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      );

      final body = jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": "Generate an image: $prompt"}
            ]
          }
        ]
      });

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? base64Image;

        if (data['candidates'] != null && (data['candidates'] as List).isNotEmpty) {
          final candidate = data['candidates'][0];
          final parts = candidate['content']?['parts'] as List?;
          if (parts != null) {
            for (var part in parts) {
              if (part['inlineData'] != null && part['inlineData']['data'] != null) {
                base64Image = part['inlineData']['data'];
                break;
              } else if (part['inline_data'] != null && part['inline_data']['data'] != null) {
                base64Image = part['inline_data']['data'];
                break;
              }
            }
          }
        }

        if (base64Image != null && base64Image.isNotEmpty) {
          return await _uploadBase64ToImgBB(base64Image);
        } else {
          print("Model $model response did not contain inlineData image: ${response.body}");
        }
      } else {
        print("Model $model (:generateContent) -> Status ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("Model $model (:generateContent) Exception: $e");
    }
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
