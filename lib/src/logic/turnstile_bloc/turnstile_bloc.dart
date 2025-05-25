import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:realtime_face_recognition/src/network/turnustile_network_service.dart';

part 'turnstile_event.dart';

part 'turnstile_state.dart';

class TurnstileBloc extends Bloc<TurnstileEvent, TurnstileState> {
  final TurnstileNetworkService _turnstileNetworkService =
      TurnstileNetworkService();

  TurnstileBloc() : super(TurnstileInitial()) {
    on<CallTurnstile>(_callTurnstile);
    on<ResetTurnstile>(_resetTurnstile);
  }

  Future<void> _callTurnstile(
      CallTurnstile event, Emitter<TurnstileState> emit) async {
    try {
      emit(TurnstileLoading());
      await _turnstileNetworkService.callTurnstile();

      emit(TurnstileSuccess());
      
      await Future.delayed(const Duration(seconds: 3));
      if (!emit.isDone) {
        emit(TurnstileInitial());
      }
    } catch (exception) {
      emit(TurnstileError(exception.toString()));
      
      await Future.delayed(const Duration(seconds: 5));
      if (!emit.isDone) {
        emit(TurnstileInitial());
      }
    }
  }
  
  void _resetTurnstile(ResetTurnstile event, Emitter<TurnstileState> emit) {
    emit(TurnstileInitial());
  }
}
