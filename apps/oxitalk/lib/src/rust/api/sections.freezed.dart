// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sections.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SectionsUpdate {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SectionsUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'SectionsUpdate()';
}


}

/// @nodoc
class $SectionsUpdateCopyWith<$Res>  {
$SectionsUpdateCopyWith(SectionsUpdate _, $Res Function(SectionsUpdate) __);
}


/// Adds pattern-matching-related methods to [SectionsUpdate].
extension SectionsUpdatePatterns on SectionsUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SectionsUpdate_Settings value)?  settings,TResult Function( SectionsUpdate_Rooms value)?  rooms,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SectionsUpdate_Settings() when settings != null:
return settings(_that);case SectionsUpdate_Rooms() when rooms != null:
return rooms(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SectionsUpdate_Settings value)  settings,required TResult Function( SectionsUpdate_Rooms value)  rooms,}){
final _that = this;
switch (_that) {
case SectionsUpdate_Settings():
return settings(_that);case SectionsUpdate_Rooms():
return rooms(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SectionsUpdate_Settings value)?  settings,TResult? Function( SectionsUpdate_Rooms value)?  rooms,}){
final _that = this;
switch (_that) {
case SectionsUpdate_Settings() when settings != null:
return settings(_that);case SectionsUpdate_Rooms() when rooms != null:
return rooms(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( SectionSettings settings)?  settings,TResult Function( List<RoomTags> rooms)?  rooms,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SectionsUpdate_Settings() when settings != null:
return settings(_that.settings);case SectionsUpdate_Rooms() when rooms != null:
return rooms(_that.rooms);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( SectionSettings settings)  settings,required TResult Function( List<RoomTags> rooms)  rooms,}) {final _that = this;
switch (_that) {
case SectionsUpdate_Settings():
return settings(_that.settings);case SectionsUpdate_Rooms():
return rooms(_that.rooms);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( SectionSettings settings)?  settings,TResult? Function( List<RoomTags> rooms)?  rooms,}) {final _that = this;
switch (_that) {
case SectionsUpdate_Settings() when settings != null:
return settings(_that.settings);case SectionsUpdate_Rooms() when rooms != null:
return rooms(_that.rooms);case _:
  return null;

}
}

}

/// @nodoc


class SectionsUpdate_Settings extends SectionsUpdate {
  const SectionsUpdate_Settings({required this.settings}): super._();
  

 final  SectionSettings settings;

/// Create a copy of SectionsUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SectionsUpdate_SettingsCopyWith<SectionsUpdate_Settings> get copyWith => _$SectionsUpdate_SettingsCopyWithImpl<SectionsUpdate_Settings>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SectionsUpdate_Settings&&(identical(other.settings, settings) || other.settings == settings));
}


@override
int get hashCode {
    return Object.hash(runtimeType,settings);
}

@override
String toString() {
    return 'SectionsUpdate.settings(settings: $settings)';
}


}

/// @nodoc
abstract mixin class $SectionsUpdate_SettingsCopyWith<$Res> implements $SectionsUpdateCopyWith<$Res> {
  factory $SectionsUpdate_SettingsCopyWith(SectionsUpdate_Settings value, $Res Function(SectionsUpdate_Settings) _then) = _$SectionsUpdate_SettingsCopyWithImpl;
@useResult
$Res call({
 SectionSettings settings
});




}
/// @nodoc
class _$SectionsUpdate_SettingsCopyWithImpl<$Res>
    implements $SectionsUpdate_SettingsCopyWith<$Res> {
  _$SectionsUpdate_SettingsCopyWithImpl(this._self, this._then);

  final SectionsUpdate_Settings _self;
  final $Res Function(SectionsUpdate_Settings) _then;

/// Create a copy of SectionsUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? settings = null,}) {
  return _then(SectionsUpdate_Settings(
settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as SectionSettings,
  ));
}


}

/// @nodoc


class SectionsUpdate_Rooms extends SectionsUpdate {
  const SectionsUpdate_Rooms({required  List<RoomTags> rooms}): _rooms = rooms,super._();
  

 final  List<RoomTags> _rooms;
 List<RoomTags> get rooms {
  if (_rooms is EqualUnmodifiableListView) return _rooms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rooms);
}


/// Create a copy of SectionsUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SectionsUpdate_RoomsCopyWith<SectionsUpdate_Rooms> get copyWith => _$SectionsUpdate_RoomsCopyWithImpl<SectionsUpdate_Rooms>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SectionsUpdate_Rooms&&const DeepCollectionEquality().equals(other.rooms, _rooms));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_rooms));
}

@override
String toString() {
    return 'SectionsUpdate.rooms(rooms: $rooms)';
}


}

/// @nodoc
abstract mixin class $SectionsUpdate_RoomsCopyWith<$Res> implements $SectionsUpdateCopyWith<$Res> {
  factory $SectionsUpdate_RoomsCopyWith(SectionsUpdate_Rooms value, $Res Function(SectionsUpdate_Rooms) _then) = _$SectionsUpdate_RoomsCopyWithImpl;
@useResult
$Res call({
 List<RoomTags> rooms
});




}
/// @nodoc
class _$SectionsUpdate_RoomsCopyWithImpl<$Res>
    implements $SectionsUpdate_RoomsCopyWith<$Res> {
  _$SectionsUpdate_RoomsCopyWithImpl(this._self, this._then);

  final SectionsUpdate_Rooms _self;
  final $Res Function(SectionsUpdate_Rooms) _then;

/// Create a copy of SectionsUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rooms = null,}) {
  return _then(SectionsUpdate_Rooms(
rooms: null == rooms ? _self._rooms : rooms // ignore: cast_nullable_to_non_nullable
as List<RoomTags>,
  ));
}


}

// dart format on
