import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiService {
  final String apiKey;
  static const String _imgBBKey = "d06e36c9de1d91a12a0c824e8c8837e4";
  static const String _endpoint =
      "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict";

  ApiService(this.apiKey);

  Future<String?> generateImage({
    required String prompt,
    required File referenceImage,
  }) async {
    try {
      final uri = Uri.parse('$_endpoint?key=$apiKey');

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
        final String base64Image =
            data['predictions'][0]['bytesBase64Encoded'];

        // Upload base64 image to ImgBB to get a permanent URL for History & Display
        return await _uploadBase64ToImgBB(base64Image);
      } else {
        print("Gemini Generation Failed: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      print("Generation exception: $e");
      return null;
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
