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
    // Attempt 1: Google AI Studio :generateImages method
    String? result = await _generateWithGenerateImages(prompt);
    if (result != null) return result;

    // Attempt 2: Fallback to :predict method
    result = await _generateWithPredict(prompt);
    if (result != null) return result;

    return null;
  }

  Future<String?> _generateWithGenerateImages(String prompt) async {
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:generateImages?key=$apiKey',
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
        print("generateImages Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("generateImages Exception: $e");
    }
    return null;
  }

  Future<String?> _generateWithPredict(String prompt) async {
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict?key=$apiKey',
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
        print("predict Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("predict Exception: $e");
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
