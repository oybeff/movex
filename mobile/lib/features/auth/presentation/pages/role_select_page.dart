import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';

class RoleSelectPage extends StatelessWidget {
  const RoleSelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.white,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.construction,
                        size: 60,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  // Container(
                  //   decoration: BoxDecoration(
                  //     color: Colors.white.withOpacity(0.9),
                  //     shape: BoxShape.circle,
                  //     boxShadow: [
                  //       BoxShadow(
                  //         color: Colors.black.withOpacity(0.1),
                  //         blurRadius: 10,
                  //         spreadRadius: 2,
                  //       ),
                  //     ],
                  //   ),
                  //   padding: const EdgeInsets.all(24),
                  //   child: const Icon(
                  //     Icons.construction,
                  //     size: 80,
                  //     color: AppColors.primaryGreen,
                  //   ),
                  // ),
                  const SizedBox(height: 40),
                    
                    // Sarlavha
                    Text(
                      'role_select.title'.tr(),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  const SizedBox(height: 40),

                  // Mijoz tugmasi.
                  //
                  // Rol KEYINGI ekranga uzatiladi. Ilgari ikkala tugma ham
                  // shunchaki '/login' ga olib borardi, rol esa yo'lda
                  // yo'qolardi va ro'yxatdan o'tishda doim 'client' qo'yilardi:
                  // "Texnika egasi" ni tanlagan odam mijoz bo'lib qolardi —
                  // dashboard ham, texnika qo'shish ham, sovg'a ham yo'q.
                  ElevatedButton.icon(
                    onPressed: () => context.push('/login', extra: 'client'),
                    icon: const Icon(Icons.person, size: 22),
                    label: Text(
                      'role_select.client'.tr(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryGreen,
                      side: const BorderSide(color: AppColors.primaryGreen, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Texnika egasi tugmasi
                  ElevatedButton.icon(
                    onPressed: () => context.push('/login', extra: 'owner'),
                    icon: const Icon(Icons.engineering, size: 22),
                    label: Text(
                      'role_select.owner'.tr(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryGreen,
                      side: const BorderSide(color: AppColors.primaryGreen, width: 1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
