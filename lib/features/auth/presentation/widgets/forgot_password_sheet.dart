import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/validators.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/webview/presentation/screens/campus_webview_screen.dart';

class ForgotPasswordSheet extends ConsumerStatefulWidget {
  final String? initialIdentifier;

  const ForgotPasswordSheet({
    super.key,
    this.initialIdentifier,
  });

  @override
  ConsumerState<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<ForgotPasswordSheet> {
  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  late final TextEditingController _identifierController;
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _codeSent = false;
  bool _obscureNewPass = true;
  bool _obscureConfirmPass = true;
  String? _dispatchedEmail;

  @override
  void initState() {
    super.initState();
    _identifierController = TextEditingController(text: widget.initialIdentifier ?? '');
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _requestCode() async {
    if (!(_step1FormKey.currentState?.validate() ?? false)) return;

    final identifier = _identifierController.text.trim();
    final success = await ref
        .read(authNotifierProvider.notifier)
        .requestPasswordReset(identifier);

    if (success && mounted) {
      setState(() {
        _codeSent = true;
        _dispatchedEmail = identifier.contains('@') ? identifier : '$identifier@diu.edu.bd';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset code & link sent to your DIU email: $_dispatchedEmail'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (mounted) {
      final errorMsg = ref.read(authNotifierProvider).errorMessage ?? 'Unable to send reset code. Please check your Student ID or Email.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _resetPassword() async {
    if (!(_step2FormKey.currentState?.validate() ?? false)) return;

    final identifier = _identifierController.text.trim();
    final otp = _otpController.text.trim();
    final newPass = _newPasswordController.text;

    final success = await ref
        .read(authNotifierProvider.notifier)
        .verifyAndResetPassword(
          identifier: identifier,
          otp: otp,
          newPassword: newPass,
        );

    if (success && mounted) {
      Navigator.of(context).pop(identifier);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Password reset successful! Please sign in with your new password.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    } else if (mounted) {
      final errorMsg = ref.read(authNotifierProvider).errorMessage ?? 'Password reset failed. Please check the code and try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixed.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_reset, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _codeSent ? 'Enter Reset Code' : 'Forgot Password?',
                        style: AppTypography.headlineSm.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _codeSent
                            ? 'Verification code sent to your DIU email'
                            : 'Recover your DIU student account password',
                        style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (authState.errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        authState.errorMessage!,
                        style: AppTypography.bodySm.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),

            // Step 1: Identifier input
            if (!_codeSent)
              Form(
                key: _step1FormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'DIU Student ID or University Email',
                      style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _identifierController,
                      validator: Validators.validateLoginIdentifier,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _requestCode(),
                      decoration: const InputDecoration(
                        hintText: 'e.g. 201-15-14285 or student@diu.edu.bd',
                        prefixIcon: Icon(Icons.badge_outlined, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We will dispatch a 6-digit password reset code to your official @diu.edu.bd student email address.',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: authState.isLoading ? null : _requestCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: authState.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Send Reset Code to DIU Email'),
                    ),
                  ],
                ),
              )
            else
              // Step 2: Code + New Password Form
              Form(
                key: _step2FormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryFixed.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mark_email_read_outlined,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Security Code Dispatched',
                                  style: AppTypography.labelMd.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Please check ${_dispatchedEmail ?? 'your DIU email'} inbox for the 6-digit verification code.',
                                  style: AppTypography.labelSm.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Reset Code
                    Text(
                      '6-Digit Reset Code',
                      style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _otpController,
                      validator: Validators.validateOtp,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineSm.copyWith(
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      decoration: const InputDecoration(
                        hintText: '••••••',
                        counterText: '',
                        prefixIcon: Icon(Icons.pin, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // New Password
                    Text(
                      'New Password',
                      style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _newPasswordController,
                      validator: Validators.validatePassword,
                      obscureText: _obscureNewPass,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: 'At least 6 characters',
                        prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNewPass ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.outline,
                          ),
                          onPressed: () => setState(() => _obscureNewPass = !_obscureNewPass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Confirm New Password
                    Text(
                      'Confirm New Password',
                      style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _confirmPasswordController,
                      validator: (v) => Validators.validateConfirmPassword(
                        v,
                        _newPasswordController.text,
                      ),
                      obscureText: _obscureConfirmPass,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _resetPassword(),
                      decoration: InputDecoration(
                        hintText: 'Re-enter your new password',
                        prefixIcon: const Icon(Icons.lock_reset, color: AppColors.primary),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPass ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.outline,
                          ),
                          onPressed: () =>
                              setState(() => _obscureConfirmPass = !_obscureConfirmPass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: authState.isLoading ? null : _resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: authState.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Update Password & Sign In'),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _codeSent = false),
                          child: const Text('Change ID / Email'),
                        ),
                        TextButton.icon(
                          onPressed: _openWebmail,
                          icon: const Icon(Icons.mail_outline, size: 16),
                          label: const Text('Check DIU Webmail'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
