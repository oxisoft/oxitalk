//! The one error type every fallible API call returns. Dart gets it as a sealed exception
//! class, so the app matches on the case, never on the message.

use std::fmt;

use matrix_sdk::{ClientBuildError, HttpError, IdParseError, reqwest, ruma::api::error::ErrorKind};
use matrix_sdk_sqlite::OpenStoreError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreError {
    /// The homeserver URL can't be used: it doesn't parse, or the server is not a Matrix
    /// homeserver with Simplified Sliding Sync.
    InvalidHomeserver { message: String },
    /// The server could not be reached.
    Network { message: String },
    /// The server refused the request, e.g. a wrong user name or password at login.
    Forbidden { message: String },
    /// The access token is no longer valid; the user has to log in again.
    SessionExpired,
    /// The store exists but can't be opened with the given passphrase.
    WrongStorePassphrase,
    /// A user or room ID that doesn't parse.
    InvalidId { id: String },
    /// No room with this ID is known to the session.
    RoomNotFound { room_id: String },
    /// The recovery key or security phrase is not the account's.
    WrongRecoveryKey,
    /// The account has no recovery set up, so there is no key to enter.
    RecoveryNotSetUp,
    /// Anything else. The message is for logs, not for the user.
    Internal { message: String },
}

impl fmt::Display for CoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidHomeserver { message } => write!(f, "invalid homeserver: {message}"),
            Self::Network { message } => write!(f, "network error: {message}"),
            Self::Forbidden { message } => write!(f, "forbidden: {message}"),
            Self::SessionExpired => f.write_str("the session has expired"),
            Self::WrongStorePassphrase => f.write_str("wrong store passphrase"),
            Self::InvalidId { id } => write!(f, "invalid ID: {id}"),
            Self::RoomNotFound { room_id } => write!(f, "room not found: {room_id}"),
            Self::WrongRecoveryKey => f.write_str("wrong recovery key"),
            Self::RecoveryNotSetUp => f.write_str("recovery is not set up"),
            Self::Internal { message } => write!(f, "internal error: {message}"),
        }
    }
}

impl std::error::Error for CoreError {}

impl CoreError {
    pub(crate) fn internal(error: &impl fmt::Display) -> Self {
        Self::Internal {
            message: error.to_string(),
        }
    }

    pub(crate) fn from_sdk(error: &matrix_sdk::Error) -> Self {
        let connection = matches!(
            error,
            matrix_sdk::Error::Http(http) if matches!(http.as_ref(), HttpError::Reqwest(e) if is_connection(e))
        );
        Self::from_http(error.client_api_error_kind(), connection, error)
    }

    /// Maps a server error by its `errcode`, and a failed connection to [`Self::Network`].
    fn from_http(kind: Option<&ErrorKind>, is_connection: bool, error: &impl fmt::Display) -> Self {
        let message = error.to_string();
        match kind {
            Some(ErrorKind::Forbidden) => Self::Forbidden { message },
            Some(ErrorKind::UnknownToken(_)) => Self::SessionExpired,
            _ if is_connection => Self::Network { message },
            _ => Self::Internal { message },
        }
    }
}

fn is_connection(error: &reqwest::Error) -> bool {
    error.is_connect() || error.is_timeout() || error.is_request()
}

impl From<HttpError> for CoreError {
    fn from(error: HttpError) -> Self {
        let connection = matches!(&error, HttpError::Reqwest(e) if is_connection(e));
        Self::from_http(error.client_api_error_kind(), connection, &error)
    }
}

impl From<matrix_sdk::Error> for CoreError {
    fn from(error: matrix_sdk::Error) -> Self {
        Self::from_sdk(&error)
    }
}

impl From<ClientBuildError> for CoreError {
    fn from(error: ClientBuildError) -> Self {
        match error {
            ClientBuildError::SqliteStore(OpenStoreError::InitCipher(_)) => {
                Self::WrongStorePassphrase
            }
            ClientBuildError::Url(_) | ClientBuildError::InvalidServerName => {
                Self::InvalidHomeserver {
                    message: error.to_string(),
                }
            }
            ClientBuildError::Http(http) => http.into(),
            other => Self::internal(&other),
        }
    }
}

/// Parses a Matrix ID, reporting the input itself if it doesn't parse.
pub(crate) fn parse_id<T>(id: &str) -> Result<T, CoreError>
where
    T: TryFrom<String, Error = IdParseError>,
{
    T::try_from(id.to_owned()).map_err(|_| CoreError::InvalidId { id: id.to_owned() })
}

impl From<matrix_sdk_ui::timeline::Error> for CoreError {
    fn from(error: matrix_sdk_ui::timeline::Error) -> Self {
        Self::internal(&error)
    }
}

#[cfg(test)]
mod tests {
    use matrix_sdk::ruma::api::error::UnknownTokenErrorData;

    use super::*;

    #[test]
    fn forbidden_and_unknown_token_map_by_errcode() {
        let forbidden = CoreError::from_http(Some(&ErrorKind::Forbidden), false, &"nope");
        assert_eq!(
            forbidden,
            CoreError::Forbidden {
                message: "nope".to_owned()
            }
        );

        let expired = CoreError::from_http(
            Some(&ErrorKind::UnknownToken(UnknownTokenErrorData::default())),
            false,
            &"gone",
        );
        assert_eq!(expired, CoreError::SessionExpired);
    }

    #[test]
    fn a_failed_connection_is_a_network_error() {
        let error = CoreError::from_http(None, true, &"refused");
        assert_eq!(
            error,
            CoreError::Network {
                message: "refused".to_owned()
            }
        );
    }

    #[test]
    fn other_errors_are_internal() {
        let error = CoreError::from_http(Some(&ErrorKind::UserInUse), false, &"taken");
        assert_eq!(
            error,
            CoreError::Internal {
                message: "taken".to_owned()
            }
        );
    }

    #[test]
    fn an_id_that_does_not_parse_is_reported_as_given() {
        assert_eq!(
            parse_id::<ruma::OwnedUserId>("not-a-user"),
            Err(CoreError::InvalidId {
                id: "not-a-user".to_owned()
            })
        );
    }

    #[test]
    fn display_names_the_case() {
        assert_eq!(
            CoreError::WrongStorePassphrase.to_string(),
            "wrong store passphrase"
        );
        assert_eq!(
            CoreError::RoomNotFound {
                room_id: "!a:b".to_owned()
            }
            .to_string(),
            "room not found: !a:b"
        );
    }
}
