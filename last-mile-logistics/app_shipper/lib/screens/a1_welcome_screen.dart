import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'registration_screen.dart';

class A1WelcomeScreen extends StatelessWidget {
  const A1WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.local_shipping_outlined,
                                  color: Colors.white,
                                  size: 27,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'TVD Logistics',
                                      style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                    Text(
                                      'Ứng dụng dành cho tài xế',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 42),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryFixed,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              'ĐỒNG HÀNH TRÊN MỌI TUYẾN GIAO',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: .8,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Nhận nhiệm vụ.\nGiao hàng thuận tiện.',
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.15,
                              letterSpacing: -1.3,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Công việc, giao nhận và thu hộ COD được cập nhật cùng hệ thống điều phối của đơn vị.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.7,
                              color: AppTheme.secondary,
                            ),
                          ),
                          const SizedBox(height: 30),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppTheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              children: [
                                _step(
                                  '01',
                                  Icons.assignment_outlined,
                                  'Nhận nhiệm vụ',
                                  'Theo phân công của điều phối viên.',
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Divider(height: 1),
                                ),
                                _step(
                                  '02',
                                  Icons.inventory_2_outlined,
                                  'Nhận kiện tại kho',
                                  'Đến kho, kiểm tra mã và xác nhận nhận kiện.',
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Divider(height: 1),
                                ),
                                _step(
                                  '03',
                                  Icons.task_alt,
                                  'Cập nhật kết quả',
                                  'Giao hàng, thu COD và xử lý hàng hoàn.',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    label: const Text(
                      'Đăng nhập tài xế',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const RegistrationScreen(),
                      ),
                    ),
                    child: const Text('Đăng ký tài xế'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const RegistrationStatusScreen(),
                      ),
                    ),
                    child: const Text('Theo dõi hồ sơ đăng ký'),
                  ),
                  const Text(
                    'Sử dụng tài khoản do đơn vị vận hành cấp.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppTheme.secondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(String number, IconData icon, String title, String detail) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryFixed.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number · $title',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.5,
                    color: AppTheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
