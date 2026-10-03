use std::fmt;
use std::time::Duration;

use async_compat::{Compat, CompatExt};
use bytes::Bytes;
use http::HeaderValue;
pub use http::header::AUTHORIZATION;
use http::header::HeaderName;
pub use http::{HeaderMap, StatusCode};
use reqwest::IntoUrl;
use serde::Serialize;
use serde::de::DeserializeOwned;

/// A wrapper around a `reqwest::Client` to execute requests. Returns a custom `RequestBuilder` type
/// that ensures any call to the underlying `reqwest::Client` are properly adapted so that they can
/// run outside of a Tokio context.
pub struct Client {
    wrapped: reqwest::Client,
}

/// A custom request builder that is a wrapper around a `request::RequestBuilder`. Ensures any async
/// call to the underyling `reqwest::RequestBuilder` are properly adapted to run outside of a Tokio
/// context via a call to `compat`.
pub struct RequestBuilder<'a> {
    wrapped: reqwest::RequestBuilder,
    client: &'a Client,

    prevent_sleep_reason: Option<&'static str>,
}

pub struct Request {
    wrapped: reqwest::Request,
    prevent_sleep_reason: Option<&'static str>,
}

/// A wrapper around a `reqwest::Response` that ensures any async calls to the underlying `Response`
/// a properly adapted to be run outside of a Tokio context.
pub struct Response(reqwest::Response);

impl Default for Client {
    fn default() -> Self {
        Self::new()
    }
}

impl Client {
    pub fn new() -> Self {
        let mut builder = reqwest::Client::builder();

        // Set some HTTP/2-related settings that aren't available on wasm.
        {
            builder = builder
                .http2_keep_alive_interval(Duration::from_secs(60))
                // If a pong is not received within 15s, consider the connection dead.
                .http2_keep_alive_timeout(Duration::from_secs(15))
                // Send these even when there aren't active streams, to ensure that we detect
                // dead connections before we attempt to use them.
                .http2_keep_alive_while_idle(true);
        }

        Self::from_client_builder(builder).expect("should not fail to create client")
    }

    pub fn from_client_builder(client_builder: reqwest::ClientBuilder) -> reqwest::Result<Self> {
        client_builder
            .build()
            .map(|client| Self { wrapped: client })
    }

    fn builder(&self, wrapped: reqwest::RequestBuilder) -> RequestBuilder<'_> {
        RequestBuilder {
            wrapped,
            client: self,
            prevent_sleep_reason: None,
        }
    }

    pub fn get<U: IntoUrl>(&self, url: U) -> RequestBuilder<'_> {
        self.builder(self.wrapped.get(url))
    }

    pub fn post<U: IntoUrl>(&self, url: U) -> RequestBuilder<'_> {
        self.builder(self.wrapped.post(url))
    }

    pub fn put<U: IntoUrl>(&self, url: U) -> RequestBuilder<'_> {
        self.builder(self.wrapped.put(url))
    }

    pub fn patch<U: IntoUrl>(&self, url: U) -> RequestBuilder<'_> {
        self.builder(self.wrapped.patch(url))
    }

    pub fn delete<U: IntoUrl>(&self, url: U) -> RequestBuilder<'_> {
        self.builder(self.wrapped.delete(url))
    }

    pub async fn execute(&self, request: Request) -> reqwest::Result<Response> {
        self.execute_inner(request).await
    }

    /// Core request execution logic shared by all platforms.
    async fn execute_inner(&self, request: Request) -> reqwest::Result<Response> {
        let Request {
            wrapped: request,
            prevent_sleep_reason,
        } = request;

        let _guard = prevent_sleep_reason.map(prevent_sleep::prevent_sleep);

        // Explicitly await the future before converting from tokio -> futures. This is because
        // certain calls to tokio (such as tokio::time::sleep) will panic upon creation if they
        // are not in a tokio runtime. Wrapping the call in an async block first makes sure that it
        // is lazily evaluated, ensuring that it is created within a tokio runtime.
        let result = Compat::new(async { self.wrapped.execute(request).await }).await?;

        Ok(Response(result))
    }
}

impl<'a> RequestBuilder<'a> {
    pub fn build(self) -> reqwest::Result<Request> {
        self.build_split().1
    }

    pub fn build_split(self) -> (&'a Client, reqwest::Result<Request>) {
        let request = self.wrapped.build().map(|request| Request {
            wrapped: request,
            prevent_sleep_reason: self.prevent_sleep_reason,
        });
        (self.client, request)
    }

    pub async fn send(self) -> reqwest::Result<Response> {
        let (client, request) = self.build_split();
        client.execute(request?).await
    }

    pub fn json<T: Serialize + ?Sized>(self, json: &T) -> RequestBuilder<'a> {
        Self {
            wrapped: self.wrapped.json(json),
            ..self
        }
    }

    pub fn basic_auth<U, P>(self, username: U, password: Option<P>) -> RequestBuilder<'a>
    where
        U: fmt::Display,
        P: fmt::Display,
    {
        Self {
            wrapped: self.wrapped.basic_auth(username, password),
            ..self
        }
    }

    pub fn bearer_auth<T>(self, token: T) -> RequestBuilder<'a>
    where
        T: fmt::Display,
    {
        Self {
            wrapped: self.wrapped.bearer_auth(token),
            ..self
        }
    }

    // The `timeout` argument is unused on wasm.
    pub fn timeout(self, timeout: Duration) -> RequestBuilder<'a> {
        Self {
            wrapped: self.wrapped.timeout(timeout),
            ..self
        }
    }

    pub fn header<K, V>(self, key: K, value: V) -> RequestBuilder<'a>
    where
        HeaderName: TryFrom<K>,
        <HeaderName as TryFrom<K>>::Error: Into<http::Error>,
        HeaderValue: TryFrom<V>,
        <HeaderValue as TryFrom<V>>::Error: Into<http::Error>,
    {
        Self {
            wrapped: self.wrapped.header(key, value),
            ..self
        }
    }

    pub fn body<T: Into<reqwest::Body>>(self, body: T) -> RequestBuilder<'a> {
        Self {
            wrapped: self.wrapped.body(body),
            ..self
        }
    }

    /// Prevents the system from sleeping due to idle while this request is in progress.
    ///
    /// The provided reason will be used in user-visible logging, so make sure it is
    /// descriptive and reasonably formatted (e.g. "Download request in-progress").
    pub fn prevent_sleep(self, reason: &'static str) -> RequestBuilder<'a> {
        Self {
            prevent_sleep_reason: Some(reason),
            ..self
        }
    }
}

/// An error returned from `Response::error_for_status` that includes response metadata.
/// This allows callers to inspect the response headers and body when handling errors.
#[derive(Debug)]
pub struct ResponseError {
    pub source: reqwest::Error,
    pub headers: Box<HeaderMap>,
    pub body: Option<String>,
}

impl std::fmt::Display for ResponseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.source.fmt(f)
    }
}

impl std::error::Error for ResponseError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.source)
    }
}

impl Response {
    pub async fn text(self) -> reqwest::Result<String> {
        Compat::new(async { self.0.text().compat().await }).await
    }

    pub fn status(&self) -> StatusCode {
        self.0.status()
    }

    pub async fn json<T: DeserializeOwned>(self) -> reqwest::Result<T> {
        Compat::new(async { self.0.json().compat().await }).await
    }

    /// Checks the response status and returns an error if it's not successful.
    /// Unlike `reqwest::Response::error_for_status`, this returns a `ResponseError`
    /// that includes the response headers, allowing callers to inspect them.
    pub fn error_for_status(self) -> Result<Self, ResponseError> {
        let headers = self.0.headers().clone();
        match self.0.error_for_status() {
            Ok(response) => Ok(Self(response)),
            Err(source) => Err(ResponseError {
                source,
                headers: Box::new(headers),
                body: None,
            }),
        }
    }

    /// Checks the response status and returns an error if it's not successful.
    /// Unlike `error_for_status`, this also reads and preserves the response body on errors.
    pub async fn error_for_status_with_body(self) -> Result<Self, ResponseError> {
        let headers = self.0.headers().clone();
        match self.0.error_for_status_ref() {
            Ok(_) => Ok(self),
            Err(source) => {
                let body = self.text().await.ok();
                Err(ResponseError {
                    source,
                    headers: Box::new(headers),
                    body,
                })
            }
        }
    }

    /// Returns a reference to the underlying response if the status is successful,
    /// otherwise returns an error with headers preserved.
    pub fn error_for_status_ref(&self) -> Result<&reqwest::Response, ResponseError> {
        let headers = self.0.headers().clone();
        match self.0.error_for_status_ref() {
            Ok(response) => Ok(response),
            Err(source) => Err(ResponseError {
                source,
                headers: Box::new(headers),
                body: None,
            }),
        }
    }

    pub async fn bytes(self) -> reqwest::Result<Bytes> {
        self.0.bytes().await
    }

    pub fn headers(&self) -> &http::HeaderMap {
        self.0.headers()
    }

    pub fn url(&self) -> &reqwest::Url {
        self.0.url()
    }
}

#[cfg(test)]
#[path = "lib_tests.rs"]
mod tests;
