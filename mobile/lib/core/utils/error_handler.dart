import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Extract error message from DioException or other exceptions
String getErrorMessage(dynamic error) {
  if (error is DioException) {
    // Try to get detail from response
    if (error.response?.data != null) {
      final data = error.response!.data;
      
      // If data is Map and has 'detail' key
      if (data is Map<String, dynamic> && data.containsKey('detail')) {
        return data['detail'].toString();
      }
      
      // If data is String
      if (data is String) {
        return data;
      }
    }
    
    // Fallback to DioException message
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'errors.connection_timeout'.tr();
      case DioExceptionType.sendTimeout:
        return 'errors.send_timeout'.tr();
      case DioExceptionType.receiveTimeout:
        return 'errors.receive_timeout'.tr();
      case DioExceptionType.badResponse:
        return 'errors.bad_response'.tr(args: [error.response?.statusCode.toString() ?? 'unknown']);
      case DioExceptionType.cancel:
        return 'errors.request_cancelled'.tr();
      case DioExceptionType.connectionError:
        return 'errors.connection_error'.tr();
      default:
        return error.message ?? 'errors.unknown_error'.tr();
    }
  }
  
  // For other exceptions
  return error.toString().replaceAll('Exception: ', '');
}

/// Show error dialog with extracted message
void showErrorDialog(BuildContext context, dynamic error) {
  final message = getErrorMessage(error);
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 28),
          const SizedBox(width: 10),
          Text('errors.error'.tr()),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('messages.ok'.tr()),
        ),
      ],
    ),
  );
}

/// Show success dialog
void showSuccessDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
          const SizedBox(width: 10),
          Text('messages.success'.tr()),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('messages.ok'.tr()),
        ),
      ],
    ),
  );
}

