import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';

class DriverSetupScreen extends ConsumerStatefulWidget {
  const DriverSetupScreen({super.key});

  @override
  ConsumerState<DriverSetupScreen> createState() => _DriverSetupScreenState();
}

class _DriverSetupScreenState extends ConsumerState<DriverSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nationalIdController = TextEditingController();
  final _licenseController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  XFile? _nationalIdPhoto;
  XFile? _licensePhoto;

  bool _isLoading = false;

  @override
  void dispose() {
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
        const SnackBar(content: Text('Please upload both photos.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(onboardingServiceProvider).submitDriverSetup(
            nationalId: _nationalIdController.text,
            driverLicenseNumber: _licenseController.text,
            licensePhoto: _licensePhoto!,
            nationalIdPhoto: _nationalIdPhoto!,
          );

      // Successfully submitted. Refresh tokens to get the updated JWT with is_driver=true
      await ref.read(authServiceProvider).tryRefresh();

      // Refresh onboarding state
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

  Widget _buildImagePickerField(String title, XFile? currentFile, bool isLicense) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _pickImage(isLicense),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: RideBaseTheme.offWhite,
              border: Border.all(color: RideBaseTheme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: currentFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(currentFile.path), fit: BoxFit.cover),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, color: RideBaseTheme.teal, size: 32),
                      SizedBox(height: 8),
                      Text('Tap to select photo'),
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
      appBar: AppBar(title: const Text('Driver Verification')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Almost there!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: RideBaseTheme.tealDark,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please provide your driver credentials to get verified.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _nationalIdController,
                decoration: const InputDecoration(
                  labelText: 'National ID Number',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _licenseController,
                decoration: const InputDecoration(
                  labelText: 'Driver License Number',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              _buildImagePickerField('National ID Photo', _nationalIdPhoto, false),
              const SizedBox(height: 24),
              _buildImagePickerField('Driver License Photo', _licensePhoto, true),
              const SizedBox(height: 32),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RideBaseTheme.teal,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Submit Verification'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
