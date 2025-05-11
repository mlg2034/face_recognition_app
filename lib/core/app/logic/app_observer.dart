
import 'package:flutter_bloc/flutter_bloc.dart';

class AppObserver extends BlocObserver {
  @override
  void onEvent(Bloc bloc, Object? event) {
    super.onEvent(bloc, event);
    print('bloc: $bloc , event: $event');
  }

  @override
  void onChange(BlocBase bloc , Change change){
    super.onChange(bloc, change);
    print('bloc: $bloc , onChange: $change');
  }


  @override
  void onTransition(Bloc bloc , Transition transition){
    super.onTransition(bloc, transition);

    print(transition);
  }

  @override
  void onError(BlocBase bloc , Object error, StackTrace stackTrace){
    super.onError(bloc, error, stackTrace);
    print('bloc: $bloc, error: $error, stackTrace: $stackTrace');

  }
}
