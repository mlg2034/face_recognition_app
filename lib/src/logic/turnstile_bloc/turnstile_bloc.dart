import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'turnstile_event.dart';
part 'turnstile_state.dart';

class TurnstileBloc extends Bloc<TurnstileEvent, TurnstileState> {
  TurnstileBloc() : super(TurnstileInitial()) {
    on<TurnstileEvent>((event, emit) {
      // TODO: implement event handler
    });
  }
}
