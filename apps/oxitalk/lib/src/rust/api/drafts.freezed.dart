// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'drafts.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DraftKind {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftKind);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DraftKind()';
}


}

/// @nodoc
class $DraftKindCopyWith<$Res>  {
$DraftKindCopyWith(DraftKind _, $Res Function(DraftKind) __);
}


/// Adds pattern-matching-related methods to [DraftKind].
extension DraftKindPatterns on DraftKind {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DraftKind_NewMessage value)?  newMessage,TResult Function( DraftKind_Reply value)?  reply,TResult Function( DraftKind_Edit value)?  edit,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DraftKind_NewMessage() when newMessage != null:
return newMessage(_that);case DraftKind_Reply() when reply != null:
return reply(_that);case DraftKind_Edit() when edit != null:
return edit(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DraftKind_NewMessage value)  newMessage,required TResult Function( DraftKind_Reply value)  reply,required TResult Function( DraftKind_Edit value)  edit,}){
final _that = this;
switch (_that) {
case DraftKind_NewMessage():
return newMessage(_that);case DraftKind_Reply():
return reply(_that);case DraftKind_Edit():
return edit(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DraftKind_NewMessage value)?  newMessage,TResult? Function( DraftKind_Reply value)?  reply,TResult? Function( DraftKind_Edit value)?  edit,}){
final _that = this;
switch (_that) {
case DraftKind_NewMessage() when newMessage != null:
return newMessage(_that);case DraftKind_Reply() when reply != null:
return reply(_that);case DraftKind_Edit() when edit != null:
return edit(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  newMessage,TResult Function( String eventId)?  reply,TResult Function( String eventId)?  edit,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DraftKind_NewMessage() when newMessage != null:
return newMessage();case DraftKind_Reply() when reply != null:
return reply(_that.eventId);case DraftKind_Edit() when edit != null:
return edit(_that.eventId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  newMessage,required TResult Function( String eventId)  reply,required TResult Function( String eventId)  edit,}) {final _that = this;
switch (_that) {
case DraftKind_NewMessage():
return newMessage();case DraftKind_Reply():
return reply(_that.eventId);case DraftKind_Edit():
return edit(_that.eventId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  newMessage,TResult? Function( String eventId)?  reply,TResult? Function( String eventId)?  edit,}) {final _that = this;
switch (_that) {
case DraftKind_NewMessage() when newMessage != null:
return newMessage();case DraftKind_Reply() when reply != null:
return reply(_that.eventId);case DraftKind_Edit() when edit != null:
return edit(_that.eventId);case _:
  return null;

}
}

}

/// @nodoc


class DraftKind_NewMessage extends DraftKind {
  const DraftKind_NewMessage(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftKind_NewMessage);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'DraftKind.newMessage()';
}


}




/// @nodoc


class DraftKind_Reply extends DraftKind {
  const DraftKind_Reply({required this.eventId}): super._();
  

 final  String eventId;

/// Create a copy of DraftKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DraftKind_ReplyCopyWith<DraftKind_Reply> get copyWith => _$DraftKind_ReplyCopyWithImpl<DraftKind_Reply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftKind_Reply&&(identical(other.eventId, eventId) || other.eventId == eventId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,eventId);
}

@override
String toString() {
    return 'DraftKind.reply(eventId: $eventId)';
}


}

/// @nodoc
abstract mixin class $DraftKind_ReplyCopyWith<$Res> implements $DraftKindCopyWith<$Res> {
  factory $DraftKind_ReplyCopyWith(DraftKind_Reply value, $Res Function(DraftKind_Reply) _then) = _$DraftKind_ReplyCopyWithImpl;
@useResult
$Res call({
 String eventId
});




}
/// @nodoc
class _$DraftKind_ReplyCopyWithImpl<$Res>
    implements $DraftKind_ReplyCopyWith<$Res> {
  _$DraftKind_ReplyCopyWithImpl(this._self, this._then);

  final DraftKind_Reply _self;
  final $Res Function(DraftKind_Reply) _then;

/// Create a copy of DraftKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? eventId = null,}) {
  return _then(DraftKind_Reply(
eventId: null == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DraftKind_Edit extends DraftKind {
  const DraftKind_Edit({required this.eventId}): super._();
  

 final  String eventId;

/// Create a copy of DraftKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DraftKind_EditCopyWith<DraftKind_Edit> get copyWith => _$DraftKind_EditCopyWithImpl<DraftKind_Edit>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftKind_Edit&&(identical(other.eventId, eventId) || other.eventId == eventId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,eventId);
}

@override
String toString() {
    return 'DraftKind.edit(eventId: $eventId)';
}


}

/// @nodoc
abstract mixin class $DraftKind_EditCopyWith<$Res> implements $DraftKindCopyWith<$Res> {
  factory $DraftKind_EditCopyWith(DraftKind_Edit value, $Res Function(DraftKind_Edit) _then) = _$DraftKind_EditCopyWithImpl;
@useResult
$Res call({
 String eventId
});




}
/// @nodoc
class _$DraftKind_EditCopyWithImpl<$Res>
    implements $DraftKind_EditCopyWith<$Res> {
  _$DraftKind_EditCopyWithImpl(this._self, this._then);

  final DraftKind_Edit _self;
  final $Res Function(DraftKind_Edit) _then;

/// Create a copy of DraftKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? eventId = null,}) {
  return _then(DraftKind_Edit(
eventId: null == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
