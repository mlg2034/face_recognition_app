import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:realtime_face_recognition/src/dto/create_user_dto.dart';
import 'package:realtime_face_recognition/src/services/firebase_db_service.dart';

part 'create_user_event.dart';
part 'create_user_state.dart';

class CreateUserBloc extends Bloc<CreateUserEvent, CreateUserState> {
  final FirebaseDBService _firebaseDBService = FirebaseDBService();
  CreateUserBloc() : super(CreateUserInitial()) {
    on<CreateUser>(_createUser);
  }

  Future<void>_createUser(CreateUser event , Emitter<CreateUserState>emit)async{
    emit(CreateUserLoading());
    try{
      await _firebaseDBService.addUser(event.createUserDTO);
      emit(CreateUserSuccess());
    }catch(exception){
      emit(CreateUserError(error: exception.toString()));
    }
  }
}
