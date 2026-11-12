//! Android only: hands the app's context to rustls-platform-verifier.
//!
//! The SDK's HTTP client (reqwest 0.13 with rustls) checks server certificates with
//! Android's own trust manager through rustls-platform-verifier, which calls into the JVM.
//! Without these handles the first HTTPS request panics ("Expect rustls-platform-verifier
//! to be initialized"), so signing in failed on Android. `MainActivity` calls this once,
//! before Flutter starts, through `TlsInit.init(context)`.

use jni::{
    EnvUnowned,
    errors::ThrowRuntimeExAndDefault,
    objects::{JClass, JObject},
};

/// `io.oxisoft.oxitalk.TlsInit.init(Context)`.
#[allow(
    unsafe_code,
    unreachable_pub,
    reason = "a JNI entry point: exported from the library under its exact, unmangled name"
)]
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_oxisoft_oxitalk_TlsInit_init<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    context: JObject<'caller>,
) {
    unowned_env
        .with_env(|env| rustls_platform_verifier::android::init_with_env(env, context))
        .resolve::<ThrowRuntimeExAndDefault>();
}
