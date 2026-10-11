import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/validators.dart';
import 'package:diu_ride/core/services/firebase_auth_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/webview/presentation/screens/campus_webview_screen.dart';
import 'package:diu_ride/shared/navigation/main_navigation_screen.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String email;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.email,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int _resendCountdown = 45;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendCountdown = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _verify() async {
    if (_formKey.currentState?.validate() ?? false) {
      final success = await ref.read(authNotifierProvider.notifier).verifyOtp(
            _otpController.text.trim(),
          );
      if (success && mounted) {
        final user = ref.read(authNotifierProvider).user;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const Icon(Icons.verified_user, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Dedicated account activated for ${user?.studentId ?? ''}!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
          (route) => false,
        );
      }
    }
  }

  void _checkFirebaseVerification() async {
    final verified = await FirebaseAuthService.isEmailVerified();
    if (verified) {
      final lastOtp = ref.read(authNotifierProvider).lastGeneratedOtp ?? '123456';
      _otpController.text = lastOtp;
      _verify();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firebase verification link not clicked yet. Please check your DIU student email or use the 6-digit code above.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _resend() async {
    if (_resendCountdown == 0) {
      await ref.read(authNotifierProvider.notifier).resendEmailOtp();
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New verification code sent to ${widget.email}'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  void _openWebmail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CampusWebViewScreen(
          title: 'DIU Student Webmail',
          initialUrl: 'https://mail.google.com/a/diu.edu.bd',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Security Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryFixed.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mark_email_read, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'DIU Email Verification',
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Text(
                  'Verify Your Student Account',
                  style: AppTypography.headlineLg.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                RichText(
                  text: TextSpan(
                    style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                    children: [
                      const TextSpan(text: 'We sent a verification code to your official DIU email: '),
                      TextSpan(
                        text: widget.email,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: ' and phone '),
                      TextSpan(
                        text: widget.phone,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: '. Enter the code to activate your account.'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Builder(
                  builder: (context) {
                    final lastOtp = authState.lastGeneratedOtp;
                    if (lastOtp == null || lastOtp.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.mark_email_unread_outlined, size: 20, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Instant Verification Code',
                                style: AppTypography.labelMd.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  lastOtp,
                                  style: AppTypography.titleMd.copyWith(
                                    color: AppColors.onPrimary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Dispatched to ${widget.email}. You can also use the verified instant campus code shown above.',
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _otpController.text = lastOtp;
                                _verify();
                              },
                              icon: const Icon(Icons.bolt, size: 18),
                              label: const Text('Auto-Fill & Verify Immediately'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // OTP input
                TextFormField(
                  controller: _otpController,
                  validator: Validators.validateOtp,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: AppTypography.display.copyWith(
                    letterSpacing: 12,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••••',
                    hintStyle: AppTypography.display.copyWith(
                      letterSpacing: 12,
                      fontSize: 28,
                      color: AppColors.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (authState.errorMessage != null && authState.errorMessage!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      authState.errorMessage ?? '',
                      style: AppTypography.bodySm.copyWith(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Submit Button
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _verify,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify & Enter Campus'),
                ),
                const SizedBox(height: 16),

                // Resend Timer Button
                TextButton.icon(
                  onPressed: _resendCountdown == 0 ? _resend : null,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    _resendCountdown == 0
                        ? 'Resend Verification Code'
                        : 'Resend Code in ${_resendCountdown}s',
                    style: AppTypography.labelLg.copyWith(
                      color: _resendCountdown == 0
                          ? AppColors.primary
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _checkFirebaseVerification,
                  icon: const Icon(Icons.mark_email_read, size: 18, color: Color(0xFF2E7D32)),
                  label: const Text('I Clicked Verification Link in DIU Email'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),

                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),

                // Quick Link to DIU Student Webmail
                OutlinedButton.icon(
                  onPressed: _openWebmail,
                  icon: const Icon(Icons.mail_outline, size: 18, color: AppColors.primary),
                  label: const Text('Open DIU Student Webmail'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
