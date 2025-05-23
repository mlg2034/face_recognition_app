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
  bool isNameTaken = false;
  String? nameErrorText;

  @override
  void initState() {
    super.initState();
    // Add listener to check name availability in real-time
    textEditingController.addListener(_checkNameAvailability);
  }

  @override
  void dispose() {
    textEditingController.removeListener(_checkNameAvailability);
    textEditingController.dispose();
    super.dispose();
  }

  void _checkNameAvailability() {
    final name = textEditingController.text.trim();
    if (name.isEmpty) {
      setState(() {
        isNameTaken = false;
        nameErrorText = null;
      });
      return;
    }

    final isTaken = widget.faceDetectionService.isUserRegistered(name);
    setState(() {
      isNameTaken = isTaken;
      nameErrorText = isTaken ? 'This name is already taken' : null;
    });
  }

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
                    borderSide: BorderSide(
                      color: isNameTaken ? Colors.red : Colors.grey,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isNameTaken ? Colors.red : Colors.grey,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isNameTaken ? Colors.red : Colors.blue,
                      width: 2,
                    ),
                  ),
                  prefixIcon: const Icon(Icons.person),
                  suffixIcon: textEditingController.text.trim().isNotEmpty
                    ? Icon(
                        isNameTaken ? Icons.cancel : Icons.check_circle,
                        color: isNameTaken ? Colors.red : Colors.green,
                      )
                    : null,
                  errorText: nameErrorText,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: (isRegistering || isNameTaken || textEditingController.text.trim().isEmpty) 
                    ? null 
                    : _registerFace,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (isNameTaken || textEditingController.text.trim().isEmpty) 
                      ? Colors.grey 
                      : Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isRegistering 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isNameTaken 
                          ? "Name Already Taken" 
                          : textEditingController.text.trim().isEmpty
                            ? "Enter Name"
                            : "Register Face",
                        style: const TextStyle(fontSize: 18),
                      ),
                ),
              ),
              const SizedBox(height: 10),
              if (isNameTaken)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This name is already registered. Please choose a different name.',
                          style: TextStyle(color: Colors.red[700], fontSize: 14),
                        ),
                      ),
                    ],
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No valid face data available'))
        );
        return;
      }
      
      // Check if user is already registered
      String userName = textEditingController.text.trim();
      if (widget.faceDetectionService.isUserRegistered(userName)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ User "$userName" is already registered! Please use a different name.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          )
        );
        return;
      }
      
      // Register the face without await
      widget.faceDetectionService.registerFaceEmbeddings(
        userName, 
        widget.recognition.embeddings
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $userName registered successfully'),
          backgroundColor: Colors.green,
        )
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