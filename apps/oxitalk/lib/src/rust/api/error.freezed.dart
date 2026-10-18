// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CoreError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError()';
}


}

/// @nodoc
class $CoreErrorCopyWith<$Res>  {
$CoreErrorCopyWith(CoreError _, $Res Function(CoreError) __);
}


/// Adds pattern-matching-related methods to [CoreError].
extension CoreErrorPatterns on CoreError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreError_InvalidHomeserver value)?  invalidHomeserver,TResult Function( CoreError_Network value)?  network,TResult Function( CoreError_Forbidden value)?  forbidden,TResult Function( CoreError_SessionExpired value)?  sessionExpired,TResult Function( CoreError_WrongStorePassphrase value)?  wrongStorePassphrase,TResult Function( CoreError_InvalidId value)?  invalidId,TResult Function( CoreError_RoomNotFound value)?  roomNotFound,TResult Function( CoreError_Internal value)?  internal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreError_InvalidHomeserver() when invalidHomeserver != null:
return invalidHomeserver(_that);case CoreError_Network() when network != null:
return network(_that);case CoreError_Forbidden() when forbidden != null:
return forbidden(_that);case CoreError_SessionExpired() when sessionExpired != null:
return sessionExpired(_that);case CoreError_WrongStorePassphrase() when wrongStorePassphrase != null:
return wrongStorePassphrase(_that);case CoreError_InvalidId() when invalidId != null:
return invalidId(_that);case CoreError_RoomNotFound() when roomNotFound != null:
return roomNotFound(_that);case CoreError_Internal() when internal != null:
return internal(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreError_InvalidHomeserver value)  invalidHomeserver,required TResult Function( CoreError_Network value)  network,required TResult Function( CoreError_Forbidden value)  forbidden,required TResult Function( CoreError_SessionExpired value)  sessionExpired,required TResult Function( CoreError_WrongStorePassphrase value)  wrongStorePassphrase,required TResult Function( CoreError_InvalidId value)  invalidId,required TResult Function( CoreError_RoomNotFound value)  roomNotFound,required TResult Function( CoreError_Internal value)  internal,}){
final _that = this;
switch (_that) {
case CoreError_InvalidHomeserver():
return invalidHomeserver(_that);case CoreError_Network():
return network(_that);case CoreError_Forbidden():
return forbidden(_that);case CoreError_SessionExpired():
return sessionExpired(_that);case CoreError_WrongStorePassphrase():
return wrongStorePassphrase(_that);case CoreError_InvalidId():
return invalidId(_that);case CoreError_RoomNotFound():
return roomNotFound(_that);case CoreError_Internal():
return internal(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreError_InvalidHomeserver value)?  invalidHomeserver,TResult? Function( CoreError_Network value)?  network,TResult? Function( CoreError_Forbidden value)?  forbidden,TResult? Function( CoreError_SessionExpired value)?  sessionExpired,TResult? Function( CoreError_WrongStorePassphrase value)?  wrongStorePassphrase,TResult? Function( CoreError_InvalidId value)?  invalidId,TResult? Function( CoreError_RoomNotFound value)?  roomNotFound,TResult? Function( CoreError_Internal value)?  internal,}){
final _that = this;
switch (_that) {
case CoreError_InvalidHomeserver() when invalidHomeserver != null:
return invalidHomeserver(_that);case CoreError_Network() when network != null:
return network(_that);case CoreError_Forbidden() when forbidden != null:
return forbidden(_that);case CoreError_SessionExpired() when sessionExpired != null:
return sessionExpired(_that);case CoreError_WrongStorePassphrase() when wrongStorePassphrase != null:
return wrongStorePassphrase(_that);case CoreError_InvalidId() when invalidId != null:
return invalidId(_that);case CoreError_RoomNotFound() when roomNotFound != null:
return roomNotFound(_that);case CoreError_Internal() when internal != null:
return internal(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  invalidHomeserver,TResult Function( String message)?  network,TResult Function( String message)?  forbidden,TResult Function()?  sessionExpired,TResult Function()?  wrongStorePassphrase,TResult Function( String id)?  invalidId,TResult Function( String roomId)?  roomNotFound,TResult Function( String message)?  internal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreError_InvalidHomeserver() when invalidHomeserver != null:
return invalidHomeserver(_that.message);case CoreError_Network() when network != null:
return network(_that.message);case CoreError_Forbidden() when forbidden != null:
return forbidden(_that.message);case CoreError_SessionExpired() when sessionExpired != null:
return sessionExpired();case CoreError_WrongStorePassphrase() when wrongStorePassphrase != null:
return wrongStorePassphrase();case CoreError_InvalidId() when invalidId != null:
return invalidId(_that.id);case CoreError_RoomNotFound() when roomNotFound != null:
return roomNotFound(_that.roomId);case CoreError_Internal() when internal != null:
return internal(_that.message);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  invalidHomeserver,required TResult Function( String message)  network,required TResult Function( String message)  forbidden,required TResult Function()  sessionExpired,required TResult Function()  wrongStorePassphrase,required TResult Function( String id)  invalidId,required TResult Function( String roomId)  roomNotFound,required TResult Function( String message)  internal,}) {final _that = this;
switch (_that) {
case CoreError_InvalidHomeserver():
return invalidHomeserver(_that.message);case CoreError_Network():
return network(_that.message);case CoreError_Forbidden():
return forbidden(_that.message);case CoreError_SessionExpired():
return sessionExpired();case CoreError_WrongStorePassphrase():
return wrongStorePassphrase();case CoreError_InvalidId():
return invalidId(_that.id);case CoreError_RoomNotFound():
return roomNotFound(_that.roomId);case CoreError_Internal():
return internal(_that.message);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  invalidHomeserver,TResult? Function( String message)?  network,TResult? Function( String message)?  forbidden,TResult? Function()?  sessionExpired,TResult? Function()?  wrongStorePassphrase,TResult? Function( String id)?  invalidId,TResult? Function( String roomId)?  roomNotFound,TResult? Function( String message)?  internal,}) {final _that = this;
switch (_that) {
case CoreError_InvalidHomeserver() when invalidHomeserver != null:
return invalidHomeserver(_that.message);case CoreError_Network() when network != null:
return network(_that.message);case CoreError_Forbidden() when forbidden != null:
return forbidden(_that.message);case CoreError_SessionExpired() when sessionExpired != null:
return sessionExpired();case CoreError_WrongStorePassphrase() when wrongStorePassphrase != null:
return wrongStorePassphrase();case CoreError_InvalidId() when invalidId != null:
return invalidId(_that.id);case CoreError_RoomNotFound() when roomNotFound != null:
return roomNotFound(_that.roomId);case CoreError_Internal() when internal != null:
return internal(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class CoreError_InvalidHomeserver extends CoreError {
  const CoreError_InvalidHomeserver({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_InvalidHomeserverCopyWith<CoreError_InvalidHomeserver> get copyWith => _$CoreError_InvalidHomeserverCopyWithImpl<CoreError_InvalidHomeserver>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_InvalidHomeserver&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.invalidHomeserver(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_InvalidHomeserverCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_InvalidHomeserverCopyWith(CoreError_InvalidHomeserver value, $Res Function(CoreError_InvalidHomeserver) _then) = _$CoreError_InvalidHomeserverCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_InvalidHomeserverCopyWithImpl<$Res>
    implements $CoreError_InvalidHomeserverCopyWith<$Res> {
  _$CoreError_InvalidHomeserverCopyWithImpl(this._self, this._then);

  final CoreError_InvalidHomeserver _self;
  final $Res Function(CoreError_InvalidHomeserver) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_InvalidHomeserver(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Network extends CoreError {
  const CoreError_Network({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_NetworkCopyWith<CoreError_Network> get copyWith => _$CoreError_NetworkCopyWithImpl<CoreError_Network>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Network&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.network(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_NetworkCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_NetworkCopyWith(CoreError_Network value, $Res Function(CoreError_Network) _then) = _$CoreError_NetworkCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_NetworkCopyWithImpl<$Res>
    implements $CoreError_NetworkCopyWith<$Res> {
  _$CoreError_NetworkCopyWithImpl(this._self, this._then);

  final CoreError_Network _self;
  final $Res Function(CoreError_Network) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_Network(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Forbidden extends CoreError {
  const CoreError_Forbidden({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_ForbiddenCopyWith<CoreError_Forbidden> get copyWith => _$CoreError_ForbiddenCopyWithImpl<CoreError_Forbidden>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Forbidden&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.forbidden(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_ForbiddenCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_ForbiddenCopyWith(CoreError_Forbidden value, $Res Function(CoreError_Forbidden) _then) = _$CoreError_ForbiddenCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_ForbiddenCopyWithImpl<$Res>
    implements $CoreError_ForbiddenCopyWith<$Res> {
  _$CoreError_ForbiddenCopyWithImpl(this._self, this._then);

  final CoreError_Forbidden _self;
  final $Res Function(CoreError_Forbidden) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_Forbidden(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_SessionExpired extends CoreError {
  const CoreError_SessionExpired(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_SessionExpired);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.sessionExpired()';
}


}




/// @nodoc


class CoreError_WrongStorePassphrase extends CoreError {
  const CoreError_WrongStorePassphrase(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_WrongStorePassphrase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.wrongStorePassphrase()';
}


}




/// @nodoc


class CoreError_InvalidId extends CoreError {
  const CoreError_InvalidId({required this.id}): super._();
  

 final  String id;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_InvalidIdCopyWith<CoreError_InvalidId> get copyWith => _$CoreError_InvalidIdCopyWithImpl<CoreError_InvalidId>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_InvalidId&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'CoreError.invalidId(id: $id)';
}


}

/// @nodoc
abstract mixin class $CoreError_InvalidIdCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_InvalidIdCopyWith(CoreError_InvalidId value, $Res Function(CoreError_InvalidId) _then) = _$CoreError_InvalidIdCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$CoreError_InvalidIdCopyWithImpl<$Res>
    implements $CoreError_InvalidIdCopyWith<$Res> {
  _$CoreError_InvalidIdCopyWithImpl(this._self, this._then);

  final CoreError_InvalidId _self;
  final $Res Function(CoreError_InvalidId) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(CoreError_InvalidId(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_RoomNotFound extends CoreError {
  const CoreError_RoomNotFound({required this.roomId}): super._();
  

 final  String roomId;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_RoomNotFoundCopyWith<CoreError_RoomNotFound> get copyWith => _$CoreError_RoomNotFoundCopyWithImpl<CoreError_RoomNotFound>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_RoomNotFound&&(identical(other.roomId, roomId) || other.roomId == roomId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,roomId);
}

@override
String toString() {
    return 'CoreError.roomNotFound(roomId: $roomId)';
}


}

/// @nodoc
abstract mixin class $CoreError_RoomNotFoundCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_RoomNotFoundCopyWith(CoreError_RoomNotFound value, $Res Function(CoreError_RoomNotFound) _then) = _$CoreError_RoomNotFoundCopyWithImpl;
@useResult
$Res call({
 String roomId
});




}
/// @nodoc
class _$CoreError_RoomNotFoundCopyWithImpl<$Res>
    implements $CoreError_RoomNotFoundCopyWith<$Res> {
  _$CoreError_RoomNotFoundCopyWithImpl(this._self, this._then);

  final CoreError_RoomNotFound _self;
  final $Res Function(CoreError_RoomNotFound) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? roomId = null,}) {
  return _then(CoreError_RoomNotFound(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Internal extends CoreError {
  const CoreError_Internal({required this.message}): super._();
  

 final  String message;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_InternalCopyWith<CoreError_Internal> get copyWith => _$CoreError_InternalCopyWithImpl<CoreError_Internal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Internal&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'CoreError.internal(message: $message)';
}


}

/// @nodoc
abstract mixin class $CoreError_InternalCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_InternalCopyWith(CoreError_Internal value, $Res Function(CoreError_Internal) _then) = _$CoreError_InternalCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$CoreError_InternalCopyWithImpl<$Res>
    implements $CoreError_InternalCopyWith<$Res> {
  _$CoreError_InternalCopyWithImpl(this._self, this._then);

  final CoreError_Internal _self;
  final $Res Function(CoreError_Internal) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(CoreError_Internal(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
