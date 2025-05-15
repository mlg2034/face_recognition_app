import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/src/services/face_detection_service.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';

class FaceRegistrationScreen extends StatefulWidget {
  final img.Image croppedFace;
  final Recognition recognition;
  final FaceDetectionService faceDetectionService;
  
  const FaceRegistrationScreen({
    Key? key, 
    required this.croppedFace, 
    required this.recognition,
    required this.faceDetectionService,
  }) : super(key: key);

  @override
  _FaceRegistrationScreenState createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  final TextEditingController textEditingController = TextEditingController();
  bool isRegistering = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Face Registration"),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.memory(
                    Uint8List.fromList(img.encodeBmp(widget.croppedFace)),
                    width: 250,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Text(
                "Enter a name for this face",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: textEditingController,
                decoration: InputDecoration(
                  fillColor: Colors.white, 
                  filled: true,
                  hintText: "Enter Name",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isRegistering ? null : _registerFace,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isRegistering 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Register Face",
                        style: TextStyle(fontSize: 18),
                      ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _registerFace() async {
    if (textEditingController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a name"))
      );
      return;
    }

    setState(() {
      isRegistering = true;
    });

    try {
      // Check if we have valid embeddings
      if (widget.recognition.embeddings.isEmpty) {
        print('Warning: Empty embeddings detected, attempting to regenerate...');
        
        // Prepare the image for the model - make sure it's the correct size
        img.Image preparedFace = widget.croppedFace;
        
        // Ensure face image is the expected size for the model
        if (preparedFace.width != 112 || preparedFace.height != 112) {
          preparedFace = img.copyResize(
            preparedFace, 
            width: 112, 
            height: 112,
            interpolation: img.Interpolation.cubic
          );
        }
        
        // Try to generate embeddings directly using the recognition service
        try {
          // We need to create a fake recognition with the right face
          Recognition tempRecog = Recognition(
            "temp", 
            widget.recognition.location, 
            [], 
            0.0
          );
          
          // Process through the detection service again
          // This is a workaround to regenerate embeddings
          tempRecog = widget.faceDetectionService.recognizer.recognize(
            preparedFace, 
            widget.recognition.location
          );
          
          // If we got valid embeddings, use them
          if (tempRecog.embeddings.isNotEmpty) {
            print('Successfully regenerated embeddings (length: ${tempRecog.embeddings.length})');
            
            // Register with the regenerated embeddings
            await widget.faceDetectionService.registerFace(
              textEditingController.text, 
              tempRecog.embeddings
            );
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${textEditingController.text} registered successfully'))
            );
            
            Navigator.pop(context, true);
            return;
          } else {
            throw Exception('Failed to generate valid embeddings after retry');
          }
        } catch (e) {
          print('Error regenerating embeddings: $e');
          throw Exception('Could not process face data: $e');
        }
      }
      
      // Normal registration path with existing embeddings
      await widget.faceDetectionService.registerFace(
        textEditingController.text, 
        widget.recognition.embeddings
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${textEditingController.text} registered successfully'))
      );
      
      Navigator.pop(context, true);
    } catch (e) {
      print('Error registering face: $e');
      final errorMsg = e.toString();
      final truncatedMsg = errorMsg.length > 50 ? '${errorMsg.substring(0, 50)}...' : errorMsg;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error registering face: $truncatedMsg'))
      );
    } finally {
      if (mounted) {
        setState(() {
          isRegistering = false;
        });
      }
    }
  }
} 