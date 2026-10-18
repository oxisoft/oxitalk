// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timeline.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TimelineDiff {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TimelineDiff()';
}


}

/// @nodoc
class $TimelineDiffCopyWith<$Res>  {
$TimelineDiffCopyWith(TimelineDiff _, $Res Function(TimelineDiff) __);
}


/// Adds pattern-matching-related methods to [TimelineDiff].
extension TimelineDiffPatterns on TimelineDiff {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TimelineDiff_Append value)?  append,TResult Function( TimelineDiff_Clear value)?  clear,TResult Function( TimelineDiff_PushFront value)?  pushFront,TResult Function( TimelineDiff_PushBack value)?  pushBack,TResult Function( TimelineDiff_PopFront value)?  popFront,TResult Function( TimelineDiff_PopBack value)?  popBack,TResult Function( TimelineDiff_Insert value)?  insert,TResult Function( TimelineDiff_Set value)?  set_,TResult Function( TimelineDiff_Remove value)?  remove,TResult Function( TimelineDiff_Truncate value)?  truncate,TResult Function( TimelineDiff_Reset value)?  reset,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TimelineDiff_Append() when append != null:
return append(_that);case TimelineDiff_Clear() when clear != null:
return clear(_that);case TimelineDiff_PushFront() when pushFront != null:
return pushFront(_that);case TimelineDiff_PushBack() when pushBack != null:
return pushBack(_that);case TimelineDiff_PopFront() when popFront != null:
return popFront(_that);case TimelineDiff_PopBack() when popBack != null:
return popBack(_that);case TimelineDiff_Insert() when insert != null:
return insert(_that);case TimelineDiff_Set() when set_ != null:
return set_(_that);case TimelineDiff_Remove() when remove != null:
return remove(_that);case TimelineDiff_Truncate() when truncate != null:
return truncate(_that);case TimelineDiff_Reset() when reset != null:
return reset(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TimelineDiff_Append value)  append,required TResult Function( TimelineDiff_Clear value)  clear,required TResult Function( TimelineDiff_PushFront value)  pushFront,required TResult Function( TimelineDiff_PushBack value)  pushBack,required TResult Function( TimelineDiff_PopFront value)  popFront,required TResult Function( TimelineDiff_PopBack value)  popBack,required TResult Function( TimelineDiff_Insert value)  insert,required TResult Function( TimelineDiff_Set value)  set_,required TResult Function( TimelineDiff_Remove value)  remove,required TResult Function( TimelineDiff_Truncate value)  truncate,required TResult Function( TimelineDiff_Reset value)  reset,}){
final _that = this;
switch (_that) {
case TimelineDiff_Append():
return append(_that);case TimelineDiff_Clear():
return clear(_that);case TimelineDiff_PushFront():
return pushFront(_that);case TimelineDiff_PushBack():
return pushBack(_that);case TimelineDiff_PopFront():
return popFront(_that);case TimelineDiff_PopBack():
return popBack(_that);case TimelineDiff_Insert():
return insert(_that);case TimelineDiff_Set():
return set_(_that);case TimelineDiff_Remove():
return remove(_that);case TimelineDiff_Truncate():
return truncate(_that);case TimelineDiff_Reset():
return reset(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TimelineDiff_Append value)?  append,TResult? Function( TimelineDiff_Clear value)?  clear,TResult? Function( TimelineDiff_PushFront value)?  pushFront,TResult? Function( TimelineDiff_PushBack value)?  pushBack,TResult? Function( TimelineDiff_PopFront value)?  popFront,TResult? Function( TimelineDiff_PopBack value)?  popBack,TResult? Function( TimelineDiff_Insert value)?  insert,TResult? Function( TimelineDiff_Set value)?  set_,TResult? Function( TimelineDiff_Remove value)?  remove,TResult? Function( TimelineDiff_Truncate value)?  truncate,TResult? Function( TimelineDiff_Reset value)?  reset,}){
final _that = this;
switch (_that) {
case TimelineDiff_Append() when append != null:
return append(_that);case TimelineDiff_Clear() when clear != null:
return clear(_that);case TimelineDiff_PushFront() when pushFront != null:
return pushFront(_that);case TimelineDiff_PushBack() when pushBack != null:
return pushBack(_that);case TimelineDiff_PopFront() when popFront != null:
return popFront(_that);case TimelineDiff_PopBack() when popBack != null:
return popBack(_that);case TimelineDiff_Insert() when insert != null:
return insert(_that);case TimelineDiff_Set() when set_ != null:
return set_(_that);case TimelineDiff_Remove() when remove != null:
return remove(_that);case TimelineDiff_Truncate() when truncate != null:
return truncate(_that);case TimelineDiff_Reset() when reset != null:
return reset(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<TimelineItem> values)?  append,TResult Function()?  clear,TResult Function( TimelineItem value)?  pushFront,TResult Function( TimelineItem value)?  pushBack,TResult Function()?  popFront,TResult Function()?  popBack,TResult Function( BigInt index,  TimelineItem value)?  insert,TResult Function( BigInt index,  TimelineItem value)?  set_,TResult Function( BigInt index)?  remove,TResult Function( BigInt length)?  truncate,TResult Function( List<TimelineItem> values)?  reset,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TimelineDiff_Append() when append != null:
return append(_that.values);case TimelineDiff_Clear() when clear != null:
return clear();case TimelineDiff_PushFront() when pushFront != null:
return pushFront(_that.value);case TimelineDiff_PushBack() when pushBack != null:
return pushBack(_that.value);case TimelineDiff_PopFront() when popFront != null:
return popFront();case TimelineDiff_PopBack() when popBack != null:
return popBack();case TimelineDiff_Insert() when insert != null:
return insert(_that.index,_that.value);case TimelineDiff_Set() when set_ != null:
return set_(_that.index,_that.value);case TimelineDiff_Remove() when remove != null:
return remove(_that.index);case TimelineDiff_Truncate() when truncate != null:
return truncate(_that.length);case TimelineDiff_Reset() when reset != null:
return reset(_that.values);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<TimelineItem> values)  append,required TResult Function()  clear,required TResult Function( TimelineItem value)  pushFront,required TResult Function( TimelineItem value)  pushBack,required TResult Function()  popFront,required TResult Function()  popBack,required TResult Function( BigInt index,  TimelineItem value)  insert,required TResult Function( BigInt index,  TimelineItem value)  set_,required TResult Function( BigInt index)  remove,required TResult Function( BigInt length)  truncate,required TResult Function( List<TimelineItem> values)  reset,}) {final _that = this;
switch (_that) {
case TimelineDiff_Append():
return append(_that.values);case TimelineDiff_Clear():
return clear();case TimelineDiff_PushFront():
return pushFront(_that.value);case TimelineDiff_PushBack():
return pushBack(_that.value);case TimelineDiff_PopFront():
return popFront();case TimelineDiff_PopBack():
return popBack();case TimelineDiff_Insert():
return insert(_that.index,_that.value);case TimelineDiff_Set():
return set_(_that.index,_that.value);case TimelineDiff_Remove():
return remove(_that.index);case TimelineDiff_Truncate():
return truncate(_that.length);case TimelineDiff_Reset():
return reset(_that.values);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<TimelineItem> values)?  append,TResult? Function()?  clear,TResult? Function( TimelineItem value)?  pushFront,TResult? Function( TimelineItem value)?  pushBack,TResult? Function()?  popFront,TResult? Function()?  popBack,TResult? Function( BigInt index,  TimelineItem value)?  insert,TResult? Function( BigInt index,  TimelineItem value)?  set_,TResult? Function( BigInt index)?  remove,TResult? Function( BigInt length)?  truncate,TResult? Function( List<TimelineItem> values)?  reset,}) {final _that = this;
switch (_that) {
case TimelineDiff_Append() when append != null:
return append(_that.values);case TimelineDiff_Clear() when clear != null:
return clear();case TimelineDiff_PushFront() when pushFront != null:
return pushFront(_that.value);case TimelineDiff_PushBack() when pushBack != null:
return pushBack(_that.value);case TimelineDiff_PopFront() when popFront != null:
return popFront();case TimelineDiff_PopBack() when popBack != null:
return popBack();case TimelineDiff_Insert() when insert != null:
return insert(_that.index,_that.value);case TimelineDiff_Set() when set_ != null:
return set_(_that.index,_that.value);case TimelineDiff_Remove() when remove != null:
return remove(_that.index);case TimelineDiff_Truncate() when truncate != null:
return truncate(_that.length);case TimelineDiff_Reset() when reset != null:
return reset(_that.values);case _:
  return null;

}
}

}

/// @nodoc


class TimelineDiff_Append extends TimelineDiff {
  const TimelineDiff_Append({required  List<TimelineItem> values}): _values = values,super._();
  

 final  List<TimelineItem> _values;
 List<TimelineItem> get values {
  if (_values is EqualUnmodifiableListView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_values);
}


/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDiff_AppendCopyWith<TimelineDiff_Append> get copyWith => _$TimelineDiff_AppendCopyWithImpl<TimelineDiff_Append>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_Append&&const DeepCollectionEquality().equals(other.values, _values));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_values));
}

@override
String toString() {
    return 'TimelineDiff.append(values: $values)';
}


}

/// @nodoc
abstract mixin class $TimelineDiff_AppendCopyWith<$Res> implements $TimelineDiffCopyWith<$Res> {
  factory $TimelineDiff_AppendCopyWith(TimelineDiff_Append value, $Res Function(TimelineDiff_Append) _then) = _$TimelineDiff_AppendCopyWithImpl;
@useResult
$Res call({
 List<TimelineItem> values
});




}
/// @nodoc
class _$TimelineDiff_AppendCopyWithImpl<$Res>
    implements $TimelineDiff_AppendCopyWith<$Res> {
  _$TimelineDiff_AppendCopyWithImpl(this._self, this._then);

  final TimelineDiff_Append _self;
  final $Res Function(TimelineDiff_Append) _then;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? values = null,}) {
  return _then(TimelineDiff_Append(
values: null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as List<TimelineItem>,
  ));
}


}

/// @nodoc


class TimelineDiff_Clear extends TimelineDiff {
  const TimelineDiff_Clear(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_Clear);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TimelineDiff.clear()';
}


}




/// @nodoc


class TimelineDiff_PushFront extends TimelineDiff {
  const TimelineDiff_PushFront({required this.value}): super._();
  

 final  TimelineItem value;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDiff_PushFrontCopyWith<TimelineDiff_PushFront> get copyWith => _$TimelineDiff_PushFrontCopyWithImpl<TimelineDiff_PushFront>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_PushFront&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'TimelineDiff.pushFront(value: $value)';
}


}

/// @nodoc
abstract mixin class $TimelineDiff_PushFrontCopyWith<$Res> implements $TimelineDiffCopyWith<$Res> {
  factory $TimelineDiff_PushFrontCopyWith(TimelineDiff_PushFront value, $Res Function(TimelineDiff_PushFront) _then) = _$TimelineDiff_PushFrontCopyWithImpl;
@useResult
$Res call({
 TimelineItem value
});




}
/// @nodoc
class _$TimelineDiff_PushFrontCopyWithImpl<$Res>
    implements $TimelineDiff_PushFrontCopyWith<$Res> {
  _$TimelineDiff_PushFrontCopyWithImpl(this._self, this._then);

  final TimelineDiff_PushFront _self;
  final $Res Function(TimelineDiff_PushFront) _then;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(TimelineDiff_PushFront(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as TimelineItem,
  ));
}


}

/// @nodoc


class TimelineDiff_PushBack extends TimelineDiff {
  const TimelineDiff_PushBack({required this.value}): super._();
  

 final  TimelineItem value;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDiff_PushBackCopyWith<TimelineDiff_PushBack> get copyWith => _$TimelineDiff_PushBackCopyWithImpl<TimelineDiff_PushBack>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_PushBack&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'TimelineDiff.pushBack(value: $value)';
}


}

/// @nodoc
abstract mixin class $TimelineDiff_PushBackCopyWith<$Res> implements $TimelineDiffCopyWith<$Res> {
  factory $TimelineDiff_PushBackCopyWith(TimelineDiff_PushBack value, $Res Function(TimelineDiff_PushBack) _then) = _$TimelineDiff_PushBackCopyWithImpl;
@useResult
$Res call({
 TimelineItem value
});




}
/// @nodoc
class _$TimelineDiff_PushBackCopyWithImpl<$Res>
    implements $TimelineDiff_PushBackCopyWith<$Res> {
  _$TimelineDiff_PushBackCopyWithImpl(this._self, this._then);

  final TimelineDiff_PushBack _self;
  final $Res Function(TimelineDiff_PushBack) _then;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(TimelineDiff_PushBack(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as TimelineItem,
  ));
}


}

/// @nodoc


class TimelineDiff_PopFront extends TimelineDiff {
  const TimelineDiff_PopFront(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_PopFront);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TimelineDiff.popFront()';
}


}




/// @nodoc


class TimelineDiff_PopBack extends TimelineDiff {
  const TimelineDiff_PopBack(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_PopBack);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TimelineDiff.popBack()';
}


}




/// @nodoc


class TimelineDiff_Insert extends TimelineDiff {
  const TimelineDiff_Insert({required this.index, required this.value}): super._();
  

 final  BigInt index;
 final  TimelineItem value;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDiff_InsertCopyWith<TimelineDiff_Insert> get copyWith => _$TimelineDiff_InsertCopyWithImpl<TimelineDiff_Insert>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_Insert&&(identical(other.index, index) || other.index == index)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,value);
}

@override
String toString() {
    return 'TimelineDiff.insert(index: $index, value: $value)';
}


}

/// @nodoc
abstract mixin class $TimelineDiff_InsertCopyWith<$Res> implements $TimelineDiffCopyWith<$Res> {
  factory $TimelineDiff_InsertCopyWith(TimelineDiff_Insert value, $Res Function(TimelineDiff_Insert) _then) = _$TimelineDiff_InsertCopyWithImpl;
@useResult
$Res call({
 BigInt index, TimelineItem value
});




}
/// @nodoc
class _$TimelineDiff_InsertCopyWithImpl<$Res>
    implements $TimelineDiff_InsertCopyWith<$Res> {
  _$TimelineDiff_InsertCopyWithImpl(this._self, this._then);

  final TimelineDiff_Insert _self;
  final $Res Function(TimelineDiff_Insert) _then;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? index = null,Object? value = null,}) {
  return _then(TimelineDiff_Insert(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as TimelineItem,
  ));
}


}

/// @nodoc


class TimelineDiff_Set extends TimelineDiff {
  const TimelineDiff_Set({required this.index, required this.value}): super._();
  

 final  BigInt index;
 final  TimelineItem value;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDiff_SetCopyWith<TimelineDiff_Set> get copyWith => _$TimelineDiff_SetCopyWithImpl<TimelineDiff_Set>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_Set&&(identical(other.index, index) || other.index == index)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,value);
}

@override
String toString() {
    return 'TimelineDiff.set_(index: $index, value: $value)';
}


}

/// @nodoc
abstract mixin class $TimelineDiff_SetCopyWith<$Res> implements $TimelineDiffCopyWith<$Res> {
  factory $TimelineDiff_SetCopyWith(TimelineDiff_Set value, $Res Function(TimelineDiff_Set) _then) = _$TimelineDiff_SetCopyWithImpl;
@useResult
$Res call({
 BigInt index, TimelineItem value
});




}
/// @nodoc
class _$TimelineDiff_SetCopyWithImpl<$Res>
    implements $TimelineDiff_SetCopyWith<$Res> {
  _$TimelineDiff_SetCopyWithImpl(this._self, this._then);

  final TimelineDiff_Set _self;
  final $Res Function(TimelineDiff_Set) _then;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? index = null,Object? value = null,}) {
  return _then(TimelineDiff_Set(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as TimelineItem,
  ));
}


}

/// @nodoc


class TimelineDiff_Remove extends TimelineDiff {
  const TimelineDiff_Remove({required this.index}): super._();
  

 final  BigInt index;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDiff_RemoveCopyWith<TimelineDiff_Remove> get copyWith => _$TimelineDiff_RemoveCopyWithImpl<TimelineDiff_Remove>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_Remove&&(identical(other.index, index) || other.index == index));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index);
}

@override
String toString() {
    return 'TimelineDiff.remove(index: $index)';
}


}

/// @nodoc
abstract mixin class $TimelineDiff_RemoveCopyWith<$Res> implements $TimelineDiffCopyWith<$Res> {
  factory $TimelineDiff_RemoveCopyWith(TimelineDiff_Remove value, $Res Function(TimelineDiff_Remove) _then) = _$TimelineDiff_RemoveCopyWithImpl;
@useResult
$Res call({
 BigInt index
});




}
/// @nodoc
class _$TimelineDiff_RemoveCopyWithImpl<$Res>
    implements $TimelineDiff_RemoveCopyWith<$Res> {
  _$TimelineDiff_RemoveCopyWithImpl(this._self, this._then);

  final TimelineDiff_Remove _self;
  final $Res Function(TimelineDiff_Remove) _then;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? index = null,}) {
  return _then(TimelineDiff_Remove(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class TimelineDiff_Truncate extends TimelineDiff {
  const TimelineDiff_Truncate({required this.length}): super._();
  

 final  BigInt length;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDiff_TruncateCopyWith<TimelineDiff_Truncate> get copyWith => _$TimelineDiff_TruncateCopyWithImpl<TimelineDiff_Truncate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_Truncate&&(identical(other.length, length) || other.length == length));
}


@override
int get hashCode {
    return Object.hash(runtimeType,length);
}

@override
String toString() {
    return 'TimelineDiff.truncate(length: $length)';
}


}

/// @nodoc
abstract mixin class $TimelineDiff_TruncateCopyWith<$Res> implements $TimelineDiffCopyWith<$Res> {
  factory $TimelineDiff_TruncateCopyWith(TimelineDiff_Truncate value, $Res Function(TimelineDiff_Truncate) _then) = _$TimelineDiff_TruncateCopyWithImpl;
@useResult
$Res call({
 BigInt length
});




}
/// @nodoc
class _$TimelineDiff_TruncateCopyWithImpl<$Res>
    implements $TimelineDiff_TruncateCopyWith<$Res> {
  _$TimelineDiff_TruncateCopyWithImpl(this._self, this._then);

  final TimelineDiff_Truncate _self;
  final $Res Function(TimelineDiff_Truncate) _then;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? length = null,}) {
  return _then(TimelineDiff_Truncate(
length: null == length ? _self.length : length // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class TimelineDiff_Reset extends TimelineDiff {
  const TimelineDiff_Reset({required  List<TimelineItem> values}): _values = values,super._();
  

 final  List<TimelineItem> _values;
 List<TimelineItem> get values {
  if (_values is EqualUnmodifiableListView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_values);
}


/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDiff_ResetCopyWith<TimelineDiff_Reset> get copyWith => _$TimelineDiff_ResetCopyWithImpl<TimelineDiff_Reset>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDiff_Reset&&const DeepCollectionEquality().equals(other.values, _values));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_values));
}

@override
String toString() {
    return 'TimelineDiff.reset(values: $values)';
}


}

/// @nodoc
abstract mixin class $TimelineDiff_ResetCopyWith<$Res> implements $TimelineDiffCopyWith<$Res> {
  factory $TimelineDiff_ResetCopyWith(TimelineDiff_Reset value, $Res Function(TimelineDiff_Reset) _then) = _$TimelineDiff_ResetCopyWithImpl;
@useResult
$Res call({
 List<TimelineItem> values
});




}
/// @nodoc
class _$TimelineDiff_ResetCopyWithImpl<$Res>
    implements $TimelineDiff_ResetCopyWith<$Res> {
  _$TimelineDiff_ResetCopyWithImpl(this._self, this._then);

  final TimelineDiff_Reset _self;
  final $Res Function(TimelineDiff_Reset) _then;

/// Create a copy of TimelineDiff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? values = null,}) {
  return _then(TimelineDiff_Reset(
values: null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as List<TimelineItem>,
  ));
}


}

/// @nodoc
mixin _$TimelineItemContent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineItemContent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TimelineItemContent()';
}


}

/// @nodoc
class $TimelineItemContentCopyWith<$Res>  {
$TimelineItemContentCopyWith(TimelineItemContent _, $Res Function(TimelineItemContent) __);
}


/// Adds pattern-matching-related methods to [TimelineItemContent].
extension TimelineItemContentPatterns on TimelineItemContent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TimelineItemContent_Message value)?  message,TResult Function( TimelineItemContent_UnableToDecrypt value)?  unableToDecrypt,TResult Function( TimelineItemContent_OtherEvent value)?  otherEvent,TResult Function( TimelineItemContent_DateDivider value)?  dateDivider,TResult Function( TimelineItemContent_ReadMarker value)?  readMarker,TResult Function( TimelineItemContent_TimelineStart value)?  timelineStart,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TimelineItemContent_Message() when message != null:
return message(_that);case TimelineItemContent_UnableToDecrypt() when unableToDecrypt != null:
return unableToDecrypt(_that);case TimelineItemContent_OtherEvent() when otherEvent != null:
return otherEvent(_that);case TimelineItemContent_DateDivider() when dateDivider != null:
return dateDivider(_that);case TimelineItemContent_ReadMarker() when readMarker != null:
return readMarker(_that);case TimelineItemContent_TimelineStart() when timelineStart != null:
return timelineStart(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TimelineItemContent_Message value)  message,required TResult Function( TimelineItemContent_UnableToDecrypt value)  unableToDecrypt,required TResult Function( TimelineItemContent_OtherEvent value)  otherEvent,required TResult Function( TimelineItemContent_DateDivider value)  dateDivider,required TResult Function( TimelineItemContent_ReadMarker value)  readMarker,required TResult Function( TimelineItemContent_TimelineStart value)  timelineStart,}){
final _that = this;
switch (_that) {
case TimelineItemContent_Message():
return message(_that);case TimelineItemContent_UnableToDecrypt():
return unableToDecrypt(_that);case TimelineItemContent_OtherEvent():
return otherEvent(_that);case TimelineItemContent_DateDivider():
return dateDivider(_that);case TimelineItemContent_ReadMarker():
return readMarker(_that);case TimelineItemContent_TimelineStart():
return timelineStart(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TimelineItemContent_Message value)?  message,TResult? Function( TimelineItemContent_UnableToDecrypt value)?  unableToDecrypt,TResult? Function( TimelineItemContent_OtherEvent value)?  otherEvent,TResult? Function( TimelineItemContent_DateDivider value)?  dateDivider,TResult? Function( TimelineItemContent_ReadMarker value)?  readMarker,TResult? Function( TimelineItemContent_TimelineStart value)?  timelineStart,}){
final _that = this;
switch (_that) {
case TimelineItemContent_Message() when message != null:
return message(_that);case TimelineItemContent_UnableToDecrypt() when unableToDecrypt != null:
return unableToDecrypt(_that);case TimelineItemContent_OtherEvent() when otherEvent != null:
return otherEvent(_that);case TimelineItemContent_DateDivider() when dateDivider != null:
return dateDivider(_that);case TimelineItemContent_ReadMarker() when readMarker != null:
return readMarker(_that);case TimelineItemContent_TimelineStart() when timelineStart != null:
return timelineStart(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( EventInfo event,  String body)?  message,TResult Function( EventInfo event)?  unableToDecrypt,TResult Function( EventInfo event)?  otherEvent,TResult Function( BigInt timestampMs)?  dateDivider,TResult Function()?  readMarker,TResult Function()?  timelineStart,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TimelineItemContent_Message() when message != null:
return message(_that.event,_that.body);case TimelineItemContent_UnableToDecrypt() when unableToDecrypt != null:
return unableToDecrypt(_that.event);case TimelineItemContent_OtherEvent() when otherEvent != null:
return otherEvent(_that.event);case TimelineItemContent_DateDivider() when dateDivider != null:
return dateDivider(_that.timestampMs);case TimelineItemContent_ReadMarker() when readMarker != null:
return readMarker();case TimelineItemContent_TimelineStart() when timelineStart != null:
return timelineStart();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( EventInfo event,  String body)  message,required TResult Function( EventInfo event)  unableToDecrypt,required TResult Function( EventInfo event)  otherEvent,required TResult Function( BigInt timestampMs)  dateDivider,required TResult Function()  readMarker,required TResult Function()  timelineStart,}) {final _that = this;
switch (_that) {
case TimelineItemContent_Message():
return message(_that.event,_that.body);case TimelineItemContent_UnableToDecrypt():
return unableToDecrypt(_that.event);case TimelineItemContent_OtherEvent():
return otherEvent(_that.event);case TimelineItemContent_DateDivider():
return dateDivider(_that.timestampMs);case TimelineItemContent_ReadMarker():
return readMarker();case TimelineItemContent_TimelineStart():
return timelineStart();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( EventInfo event,  String body)?  message,TResult? Function( EventInfo event)?  unableToDecrypt,TResult? Function( EventInfo event)?  otherEvent,TResult? Function( BigInt timestampMs)?  dateDivider,TResult? Function()?  readMarker,TResult? Function()?  timelineStart,}) {final _that = this;
switch (_that) {
case TimelineItemContent_Message() when message != null:
return message(_that.event,_that.body);case TimelineItemContent_UnableToDecrypt() when unableToDecrypt != null:
return unableToDecrypt(_that.event);case TimelineItemContent_OtherEvent() when otherEvent != null:
return otherEvent(_that.event);case TimelineItemContent_DateDivider() when dateDivider != null:
return dateDivider(_that.timestampMs);case TimelineItemContent_ReadMarker() when readMarker != null:
return readMarker();case TimelineItemContent_TimelineStart() when timelineStart != null:
return timelineStart();case _:
  return null;

}
}

}

/// @nodoc


class TimelineItemContent_Message extends TimelineItemContent {
  const TimelineItemContent_Message({required this.event, required this.body}): super._();
  

 final  EventInfo event;
 final  String body;

/// Create a copy of TimelineItemContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineItemContent_MessageCopyWith<TimelineItemContent_Message> get copyWith => _$TimelineItemContent_MessageCopyWithImpl<TimelineItemContent_Message>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineItemContent_Message&&(identical(other.event, event) || other.event == event)&&(identical(other.body, body) || other.body == body));
}


@override
int get hashCode {
    return Object.hash(runtimeType,event,body);
}

@override
String toString() {
    return 'TimelineItemContent.message(event: $event, body: $body)';
}


}

/// @nodoc
abstract mixin class $TimelineItemContent_MessageCopyWith<$Res> implements $TimelineItemContentCopyWith<$Res> {
  factory $TimelineItemContent_MessageCopyWith(TimelineItemContent_Message value, $Res Function(TimelineItemContent_Message) _then) = _$TimelineItemContent_MessageCopyWithImpl;
@useResult
$Res call({
 EventInfo event, String body
});




}
/// @nodoc
class _$TimelineItemContent_MessageCopyWithImpl<$Res>
    implements $TimelineItemContent_MessageCopyWith<$Res> {
  _$TimelineItemContent_MessageCopyWithImpl(this._self, this._then);

  final TimelineItemContent_Message _self;
  final $Res Function(TimelineItemContent_Message) _then;

/// Create a copy of TimelineItemContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,Object? body = null,}) {
  return _then(TimelineItemContent_Message(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as EventInfo,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class TimelineItemContent_UnableToDecrypt extends TimelineItemContent {
  const TimelineItemContent_UnableToDecrypt({required this.event}): super._();
  

 final  EventInfo event;

/// Create a copy of TimelineItemContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineItemContent_UnableToDecryptCopyWith<TimelineItemContent_UnableToDecrypt> get copyWith => _$TimelineItemContent_UnableToDecryptCopyWithImpl<TimelineItemContent_UnableToDecrypt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineItemContent_UnableToDecrypt&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,event);
}

@override
String toString() {
    return 'TimelineItemContent.unableToDecrypt(event: $event)';
}


}

/// @nodoc
abstract mixin class $TimelineItemContent_UnableToDecryptCopyWith<$Res> implements $TimelineItemContentCopyWith<$Res> {
  factory $TimelineItemContent_UnableToDecryptCopyWith(TimelineItemContent_UnableToDecrypt value, $Res Function(TimelineItemContent_UnableToDecrypt) _then) = _$TimelineItemContent_UnableToDecryptCopyWithImpl;
@useResult
$Res call({
 EventInfo event
});




}
/// @nodoc
class _$TimelineItemContent_UnableToDecryptCopyWithImpl<$Res>
    implements $TimelineItemContent_UnableToDecryptCopyWith<$Res> {
  _$TimelineItemContent_UnableToDecryptCopyWithImpl(this._self, this._then);

  final TimelineItemContent_UnableToDecrypt _self;
  final $Res Function(TimelineItemContent_UnableToDecrypt) _then;

/// Create a copy of TimelineItemContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,}) {
  return _then(TimelineItemContent_UnableToDecrypt(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as EventInfo,
  ));
}


}

/// @nodoc


class TimelineItemContent_OtherEvent extends TimelineItemContent {
  const TimelineItemContent_OtherEvent({required this.event}): super._();
  

 final  EventInfo event;

/// Create a copy of TimelineItemContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineItemContent_OtherEventCopyWith<TimelineItemContent_OtherEvent> get copyWith => _$TimelineItemContent_OtherEventCopyWithImpl<TimelineItemContent_OtherEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineItemContent_OtherEvent&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,event);
}

@override
String toString() {
    return 'TimelineItemContent.otherEvent(event: $event)';
}


}

/// @nodoc
abstract mixin class $TimelineItemContent_OtherEventCopyWith<$Res> implements $TimelineItemContentCopyWith<$Res> {
  factory $TimelineItemContent_OtherEventCopyWith(TimelineItemContent_OtherEvent value, $Res Function(TimelineItemContent_OtherEvent) _then) = _$TimelineItemContent_OtherEventCopyWithImpl;
@useResult
$Res call({
 EventInfo event
});




}
/// @nodoc
class _$TimelineItemContent_OtherEventCopyWithImpl<$Res>
    implements $TimelineItemContent_OtherEventCopyWith<$Res> {
  _$TimelineItemContent_OtherEventCopyWithImpl(this._self, this._then);

  final TimelineItemContent_OtherEvent _self;
  final $Res Function(TimelineItemContent_OtherEvent) _then;

/// Create a copy of TimelineItemContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,}) {
  return _then(TimelineItemContent_OtherEvent(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as EventInfo,
  ));
}


}

/// @nodoc


class TimelineItemContent_DateDivider extends TimelineItemContent {
  const TimelineItemContent_DateDivider({required this.timestampMs}): super._();
  

 final  BigInt timestampMs;

/// Create a copy of TimelineItemContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineItemContent_DateDividerCopyWith<TimelineItemContent_DateDivider> get copyWith => _$TimelineItemContent_DateDividerCopyWithImpl<TimelineItemContent_DateDivider>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineItemContent_DateDivider&&(identical(other.timestampMs, timestampMs) || other.timestampMs == timestampMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,timestampMs);
}

@override
String toString() {
    return 'TimelineItemContent.dateDivider(timestampMs: $timestampMs)';
}


}

/// @nodoc
abstract mixin class $TimelineItemContent_DateDividerCopyWith<$Res> implements $TimelineItemContentCopyWith<$Res> {
  factory $TimelineItemContent_DateDividerCopyWith(TimelineItemContent_DateDivider value, $Res Function(TimelineItemContent_DateDivider) _then) = _$TimelineItemContent_DateDividerCopyWithImpl;
@useResult
$Res call({
 BigInt timestampMs
});




}
/// @nodoc
class _$TimelineItemContent_DateDividerCopyWithImpl<$Res>
    implements $TimelineItemContent_DateDividerCopyWith<$Res> {
  _$TimelineItemContent_DateDividerCopyWithImpl(this._self, this._then);

  final TimelineItemContent_DateDivider _self;
  final $Res Function(TimelineItemContent_DateDivider) _then;

/// Create a copy of TimelineItemContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? timestampMs = null,}) {
  return _then(TimelineItemContent_DateDivider(
timestampMs: null == timestampMs ? _self.timestampMs : timestampMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class TimelineItemContent_ReadMarker extends TimelineItemContent {
  const TimelineItemContent_ReadMarker(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineItemContent_ReadMarker);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TimelineItemContent.readMarker()';
}


}




/// @nodoc


class TimelineItemContent_TimelineStart extends TimelineItemContent {
  const TimelineItemContent_TimelineStart(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineItemContent_TimelineStart);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TimelineItemContent.timelineStart()';
}


}




// dart format on
