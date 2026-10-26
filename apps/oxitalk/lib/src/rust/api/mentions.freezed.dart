// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mentions.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MessagePart {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessagePart);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'MessagePart()';
}


}

/// @nodoc
class $MessagePartCopyWith<$Res>  {
$MessagePartCopyWith(MessagePart _, $Res Function(MessagePart) __);
}


/// Adds pattern-matching-related methods to [MessagePart].
extension MessagePartPatterns on MessagePart {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MessagePart_Text value)?  text,TResult Function( MessagePart_User value)?  user,TResult Function( MessagePart_Room value)?  room,TResult Function( MessagePart_AtRoom value)?  atRoom,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MessagePart_Text() when text != null:
return text(_that);case MessagePart_User() when user != null:
return user(_that);case MessagePart_Room() when room != null:
return room(_that);case MessagePart_AtRoom() when atRoom != null:
return atRoom(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MessagePart_Text value)  text,required TResult Function( MessagePart_User value)  user,required TResult Function( MessagePart_Room value)  room,required TResult Function( MessagePart_AtRoom value)  atRoom,}){
final _that = this;
switch (_that) {
case MessagePart_Text():
return text(_that);case MessagePart_User():
return user(_that);case MessagePart_Room():
return room(_that);case MessagePart_AtRoom():
return atRoom(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MessagePart_Text value)?  text,TResult? Function( MessagePart_User value)?  user,TResult? Function( MessagePart_Room value)?  room,TResult? Function( MessagePart_AtRoom value)?  atRoom,}){
final _that = this;
switch (_that) {
case MessagePart_Text() when text != null:
return text(_that);case MessagePart_User() when user != null:
return user(_that);case MessagePart_Room() when room != null:
return room(_that);case MessagePart_AtRoom() when atRoom != null:
return atRoom(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  text,TResult Function( String userId,  String name)?  user,TResult Function( String roomId,  String? alias,  String name)?  room,TResult Function()?  atRoom,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MessagePart_Text() when text != null:
return text(_that.text);case MessagePart_User() when user != null:
return user(_that.userId,_that.name);case MessagePart_Room() when room != null:
return room(_that.roomId,_that.alias,_that.name);case MessagePart_AtRoom() when atRoom != null:
return atRoom();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  text,required TResult Function( String userId,  String name)  user,required TResult Function( String roomId,  String? alias,  String name)  room,required TResult Function()  atRoom,}) {final _that = this;
switch (_that) {
case MessagePart_Text():
return text(_that.text);case MessagePart_User():
return user(_that.userId,_that.name);case MessagePart_Room():
return room(_that.roomId,_that.alias,_that.name);case MessagePart_AtRoom():
return atRoom();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  text,TResult? Function( String userId,  String name)?  user,TResult? Function( String roomId,  String? alias,  String name)?  room,TResult? Function()?  atRoom,}) {final _that = this;
switch (_that) {
case MessagePart_Text() when text != null:
return text(_that.text);case MessagePart_User() when user != null:
return user(_that.userId,_that.name);case MessagePart_Room() when room != null:
return room(_that.roomId,_that.alias,_that.name);case MessagePart_AtRoom() when atRoom != null:
return atRoom();case _:
  return null;

}
}

}

/// @nodoc


class MessagePart_Text extends MessagePart {
  const MessagePart_Text({required this.text}): super._();
  

 final  String text;

/// Create a copy of MessagePart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessagePart_TextCopyWith<MessagePart_Text> get copyWith => _$MessagePart_TextCopyWithImpl<MessagePart_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessagePart_Text&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'MessagePart.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $MessagePart_TextCopyWith<$Res> implements $MessagePartCopyWith<$Res> {
  factory $MessagePart_TextCopyWith(MessagePart_Text value, $Res Function(MessagePart_Text) _then) = _$MessagePart_TextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$MessagePart_TextCopyWithImpl<$Res>
    implements $MessagePart_TextCopyWith<$Res> {
  _$MessagePart_TextCopyWithImpl(this._self, this._then);

  final MessagePart_Text _self;
  final $Res Function(MessagePart_Text) _then;

/// Create a copy of MessagePart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(MessagePart_Text(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MessagePart_User extends MessagePart {
  const MessagePart_User({required this.userId, required this.name}): super._();
  

 final  String userId;
 final  String name;

/// Create a copy of MessagePart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessagePart_UserCopyWith<MessagePart_User> get copyWith => _$MessagePart_UserCopyWithImpl<MessagePart_User>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessagePart_User&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,userId,name);
}

@override
String toString() {
    return 'MessagePart.user(userId: $userId, name: $name)';
}


}

/// @nodoc
abstract mixin class $MessagePart_UserCopyWith<$Res> implements $MessagePartCopyWith<$Res> {
  factory $MessagePart_UserCopyWith(MessagePart_User value, $Res Function(MessagePart_User) _then) = _$MessagePart_UserCopyWithImpl;
@useResult
$Res call({
 String userId, String name
});




}
/// @nodoc
class _$MessagePart_UserCopyWithImpl<$Res>
    implements $MessagePart_UserCopyWith<$Res> {
  _$MessagePart_UserCopyWithImpl(this._self, this._then);

  final MessagePart_User _self;
  final $Res Function(MessagePart_User) _then;

/// Create a copy of MessagePart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? name = null,}) {
  return _then(MessagePart_User(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MessagePart_Room extends MessagePart {
  const MessagePart_Room({required this.roomId, this.alias, required this.name}): super._();
  

 final  String roomId;
 final  String? alias;
 final  String name;

/// Create a copy of MessagePart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessagePart_RoomCopyWith<MessagePart_Room> get copyWith => _$MessagePart_RoomCopyWithImpl<MessagePart_Room>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessagePart_Room&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.alias, alias) || other.alias == alias)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,roomId,alias,name);
}

@override
String toString() {
    return 'MessagePart.room(roomId: $roomId, alias: $alias, name: $name)';
}


}

/// @nodoc
abstract mixin class $MessagePart_RoomCopyWith<$Res> implements $MessagePartCopyWith<$Res> {
  factory $MessagePart_RoomCopyWith(MessagePart_Room value, $Res Function(MessagePart_Room) _then) = _$MessagePart_RoomCopyWithImpl;
@useResult
$Res call({
 String roomId, String? alias, String name
});




}
/// @nodoc
class _$MessagePart_RoomCopyWithImpl<$Res>
    implements $MessagePart_RoomCopyWith<$Res> {
  _$MessagePart_RoomCopyWithImpl(this._self, this._then);

  final MessagePart_Room _self;
  final $Res Function(MessagePart_Room) _then;

/// Create a copy of MessagePart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? roomId = null,Object? alias = freezed,Object? name = null,}) {
  return _then(MessagePart_Room(
roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,alias: freezed == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MessagePart_AtRoom extends MessagePart {
  const MessagePart_AtRoom(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessagePart_AtRoom);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'MessagePart.atRoom()';
}


}




// dart format on
