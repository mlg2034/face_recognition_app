import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:realtime_face_recognition/src/model/user_model.dart';
import 'package:realtime_face_recognition/src/services/firebase_db_service.dart';

part 'get_user_list_event.dart';

part 'get_user_list_state.dart';

class GetUserListBloc extends Bloc<GetUserListEvent, GetUserListState> {
  final FirebaseDBService _firebaseDBService = FirebaseDBService();

  GetUserListBloc() : super(GetUserListInitial()) {
    on<GetUserList>(_getUserList);
  }

  Future<void> _getUserList(
      GetUserList event, Emitter<GetUserListState> emit) async {
    emit(GetUserListLoading());

    try {
      final response = await _firebaseDBService.getAllUsers();
      emit(GetUserListSuccess(response));
    } catch (exception) {
      emit(GetUserListError(exception.toString()));
    }
  }
}
