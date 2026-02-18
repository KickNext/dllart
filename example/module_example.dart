import 'package:dllart/dllart_annotations.dart';

@DllartExport('healthcheck')
Object? healthcheck() => 'ok';

@DllartExport('add_fast')
int addFast(int a, int b) => a + b;

@DllartExport('sum4_fast')
int sum4Fast(int a, int b, int c, int d) => a + b + c + d;

@DllartExport('avg2_fast')
double avg2Fast(double a, double b) => (a + b) / 2.0;
