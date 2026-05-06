import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme.dart';
import '../providers/onboarding_provider.dart';

const Color _teal = RideBaseTheme.teal;

class DriverSetupScreen extends ConsumerStatefulWidget {
  const DriverSetupScreen({super.key});

  @override
  ConsumerState<DriverSetupScreen> createState() => _DriverSetupScreenState();
}

class _DriverSetupScreenState extends ConsumerState<DriverSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _carMakeController = TextEditingController();
  final _carModelController = TextEditingController();
  final _carColourController = TextEditingController();
  final _yearController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _licenseController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  XFile? _nationalIdPhoto;
  XFile? _licensePhoto;

  bool _isLoading = false;

  @override
  void dispose() {
    _carMakeController.dispose();
    _carModelController.dispose();
    _carColourController.dispose();
    _yearController.dispose();
    _licensePlateController.dispose();
    _nationalIdController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isLicense) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (isLicense) {
          _licensePhoto = image;
        } else {
          _nationalIdPhoto = image;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_nationalIdPhoto == null || _licensePhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please upload both photos.'),
          backgroundColor: Colors.redAccent.shade100,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(onboardingServiceProvider).submitDriverSetup(
            carMake: _carMakeController.text.trim(),
            carModel: _carModelController.text.trim(),
            carColour: _carColourController.text.trim(),
            year: int.parse(_yearController.text.trim()),
            licensePlate: _licensePlateController.text.trim(),
            nationalId: _nationalIdController.text.trim(),
            driverLicenseNumber: _licenseController.text.trim(),
            licensePhoto: _licensePhoto!,
            nationalIdPhoto: _nationalIdPhoto!,
          );

      // Refresh tokens then update auth state so the drawer role badge
      // reflects is_driver=true without requiring a full sign-out/in cycle.
      await ref.read(authProvider.notifier).refreshUser();

      // Advance onboarding to the next step
      await ref.read(onboardingProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
      hintStyle: const TextStyle(color: Colors.black26),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: InputBorder.none,
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _teal, width: 2),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: _teal, width: 3),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent, width: 2),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent, width: 3),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _buildImagePicker(
      String title, String subtitle, IconData icon, XFile? currentFile, bool isLicense) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _pickImage(isLicense),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: currentFile != null ? Colors.transparent : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: currentFile != null ? _teal : Colors.grey.shade300,
                width: currentFile != null ? 2 : 1.5,
              ),
            ),
            child: currentFile != null
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          File(currentFile.path),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                      // Success overlay
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: _teal,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      // Tap to change label
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(14),
                              bottomRight: Radius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Tap to change',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _teal.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: _teal, size: 24),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'JPEG, PNG or PDF',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const SizedBox.shrink(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Icon Circle
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: _teal,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                'Driver Verification',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Subtitle
              const Text(
                'Upload your documents to get verified\nand start accepting rides.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Vehicle Details
              const _SectionHeader(title: 'Vehicle Details'),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _carMakeController,
                      decoration: _inputDecoration('Make', 'Toyota'),
                      style: const TextStyle(fontSize: 16, color: Colors.black87),
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _carModelController,
                      decoration: _inputDecoration('Model', 'Camry'),
                      style: const TextStyle(fontSize: 16, color: Colors.black87),
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _carColourController,
                      decoration: _inputDecoration('Colour', 'Silver'),
                      style: const TextStyle(fontSize: 16, color: Colors.black87),
                      validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _yearController,
                      decoration: _inputDecoration('Year', '2020'),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 16, color: Colors.black87),
                      validator: (v) {
                        if (v!.trim().isEmpty) return 'Required';
                        final y = int.tryParse(v.trim());
                        if (y == null || y < 1980 || y > DateTime.now().year + 1) {
                          return 'Invalid year';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _licensePlateController,
                decoration: _inputDecoration('License Plate', 'ABC 1234'),
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 32),

              // Documents
              const _SectionHeader(title: 'Documents'),
              const SizedBox(height: 16),

              // National ID Number
              TextFormField(
                controller: _nationalIdController,
                decoration: _inputDecoration('National ID Number', '12-345678-A-00'),
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              // Driver License Number
              TextFormField(
                controller: _licenseController,
                decoration: _inputDecoration('Driver License Number', 'DL987654'),
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 32),

              // National ID Photo
              _buildImagePicker(
                'National ID Photo',
                'Upload your National ID',
                Icons.badge_outlined,
                _nationalIdPhoto,
                false,
              ),
              const SizedBox(height: 24),

              // Driver License Photo
              _buildImagePicker(
                'Driver License Photo',
                'Upload your Driver License',
                Icons.credit_card_rounded,
                _licensePhoto,
                true,
              ),
              const SizedBox(height: 40),

              // Submit Button
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RideBaseTheme.primaryContainer,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(27),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Submit Verification',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade500,
        letterSpacing: 1.0,
      ),
    );
  }
}
