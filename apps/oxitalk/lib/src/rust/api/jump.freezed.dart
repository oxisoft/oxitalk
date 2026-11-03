// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'jump.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MessageSince {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageSince);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'MessageSince()';
}


}

/// @nodoc
class $MessageSinceCopyWith<$Res>  {
$MessageSinceCopyWith(MessageSince _, $Res Function(MessageSince) __);
}


/// Adds pattern-matching-related methods to [MessageSince].
extension MessageSincePatterns on MessageSince {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MessageSince_Found value)?  found,TResult Function( MessageSince_NoneAfter value)?  noneAfter,TResult Function( MessageSince_Unsupported value)?  unsupported,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MessageSince_Found() when found != null:
return found(_that);case MessageSince_NoneAfter() when noneAfter != null:
return noneAfter(_that);case MessageSince_Unsupported() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MessageSince_Found value)  found,required TResult Function( MessageSince_NoneAfter value)  noneAfter,required TResult Function( MessageSince_Unsupported value)  unsupported,}){
final _that = this;
switch (_that) {
case MessageSince_Found():
return found(_that);case MessageSince_NoneAfter():
return noneAfter(_that);case MessageSince_Unsupported():
return unsupported(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MessageSince_Found value)?  found,TResult? Function( MessageSince_NoneAfter value)?  noneAfter,TResult? Function( MessageSince_Unsupported value)?  unsupported,}){
final _that = this;
switch (_that) {
case MessageSince_Found() when found != null:
return found(_that);case MessageSince_NoneAfter() when noneAfter != null:
return noneAfter(_that);case MessageSince_Unsupported() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String eventId,  PlatformInt64 timestampMs)?  found,TResult Function()?  noneAfter,TResult Function()?  unsupported,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MessageSince_Found() when found != null:
return found(_that.eventId,_that.timestampMs);case MessageSince_NoneAfter() when noneAfter != null:
return noneAfter();case MessageSince_Unsupported() when unsupported != null:
return unsupported();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String eventId,  PlatformInt64 timestampMs)  found,required TResult Function()  noneAfter,required TResult Function()  unsupported,}) {final _that = this;
switch (_that) {
case MessageSince_Found():
return found(_that.eventId,_that.timestampMs);case MessageSince_NoneAfter():
return noneAfter();case MessageSince_Unsupported():
return unsupported();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String eventId,  PlatformInt64 timestampMs)?  found,TResult? Function()?  noneAfter,TResult? Function()?  unsupported,}) {final _that = this;
switch (_that) {
case MessageSince_Found() when found != null:
return found(_that.eventId,_that.timestampMs);case MessageSince_NoneAfter() when noneAfter != null:
return noneAfter();case MessageSince_Unsupported() when unsupported != null:
return unsupported();case _:
  return null;

}
}

}

/// @nodoc


class MessageSince_Found extends MessageSince {
  const MessageSince_Found({required this.eventId, required this.timestampMs}): super._();
  

 final  String eventId;
 final  PlatformInt64 timestampMs;

/// Create a copy of MessageSince
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageSince_FoundCopyWith<MessageSince_Found> get copyWith => _$MessageSince_FoundCopyWithImpl<MessageSince_Found>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageSince_Found&&(identical(other.eventId, eventId) || other.eventId == eventId)&&(identical(other.timestampMs, timestampMs) || other.timestampMs == timestampMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,eventId,timestampMs);
}

@override
String toString() {
    return 'MessageSince.found(eventId: $eventId, timestampMs: $timestampMs)';
}


}

/// @nodoc
abstract mixin class $MessageSince_FoundCopyWith<$Res> implements $MessageSinceCopyWith<$Res> {
  factory $MessageSince_FoundCopyWith(MessageSince_Found value, $Res Function(MessageSince_Found) _then) = _$MessageSince_FoundCopyWithImpl;
@useResult
$Res call({
 String eventId, PlatformInt64 timestampMs
});




}
/// @nodoc
class _$MessageSince_FoundCopyWithImpl<$Res>
    implements $MessageSince_FoundCopyWith<$Res> {
  _$MessageSince_FoundCopyWithImpl(this._self, this._then);

  final MessageSince_Found _self;
  final $Res Function(MessageSince_Found) _then;

/// Create a copy of MessageSince
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? eventId = null,Object? timestampMs = null,}) {
  return _then(MessageSince_Found(
eventId: null == eventId ? _self.eventId : eventId // ignore: cast_nullable_to_non_nullable
as String,timestampMs: null == timestampMs ? _self.timestampMs : timestampMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class MessageSince_NoneAfter extends MessageSince {
  const MessageSince_NoneAfter(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageSince_NoneAfter);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'MessageSince.noneAfter()';
}


}




/// @nodoc


class MessageSince_Unsupported extends MessageSince {
  const MessageSince_Unsupported(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageSince_Unsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'MessageSince.unsupported()';
}


}




// dart format on
