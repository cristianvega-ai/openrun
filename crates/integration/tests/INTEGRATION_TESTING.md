# Integration tests in Warp
This is a short guide into writing integration tests in Warp.

## When to add a new integration test?
Our general philosophy around how we see unit vs integration testing can be summarized as follows:
### Write unit tests when:
* Testing a single function;
* Function has minimal deps and no pty deps;
* Can run purely in rust, e.g. a parser.

### Integration testing can help:
* Test some use-case from the user perspective;
* In scenarios that are slower or require a shell.

## What makes a good integration test?
Test typically has the format:
* Setup some state in the app;
* Simulate a user action (e.g. type or click);
* Verify that the app is in the expected state.

## How to add a new integration test?
Our integration tests currently require you to work with **3** files: [integration/tests/integration.rs](integration.rs), [integration/src/bin/integration.rs](../src/bin/integration.rs), and [integration/src/test.rs](../src/test.rs). (Most tests live in `test.rs` today, but you might want to write yours in a separate file.)

Let's start with writing a *new integration test* for your feature. To do that, simply add a new method to [integration/src/bin/integration.rs](../src/bin/integration.rs). It should take **0 arguments** and **return `TestDriver`** object. You should also register it in `register_tests()` method in the same file, and later on (to ensure it's being executed) adding it to [integration/tests/integration.rs](integration.rs) in the `integration_tests!` macro. As a convention, each test method name starts with `test_` prefix (note, however, that it doesn't require the `#[test]` annotation like usual unit tests in Rust).

Now that you've made the first step, it's time to make use of the integration test framework. Let's use the following example to talk more about what's possible to do in integration tests (you'll find more explanation in the comments):

```rs
fn test_simple_example() -> TestDriver {
    new_builder() // initializes the integration test builder
        // each test can have multiple steps, which are more or less complicated,
        // for example - you can wait for a specific action to happen, like in the line below!
        .with_step(wait_for_bootstrapping(0))
        .with_step(
            // You can also create your own `TestStep`!
            TestStep::new("Run ls and verify block exists") // Each `TestStep` has a name
                // ...and later lets you specify what happens. You can verify which characters were typed:
                .with_keystrokes(&[
                    Keystroke::parse("l").unwrap(),
                    Keystroke::parse("s").unwrap(),
                    Keystroke::parse("enter").unwrap(),
                ])
                // ...set timeouts after which the test is doomed:
                .set_timeout(Duration::from_secs(5))
                // ...specify certain assertions:
                .set_assertion(Box::new(|app, window_id, presenter| {
                    let presenter = presenter.expect("presenter should be set");
                    assert!(presenter.scene().is_some());
                    let views = app.views_of_type(window_id).unwrap();
                    let terminal_view: &ViewHandle<TerminalView> = views.get(0).unwrap();
                    terminal_view.read(app, |view, _ctx| {
                        let model = view.model.lock();
                        async_assert!(
                            !model.is_block_list_empty(),
                            "Block list should not be empty"
                        )
                    })
                })),
        )
        .build()
}
```

I find `with_keystrokes` and `with_input_string` most helpful methods, so far. You can check the implementation (and expand it!) in [warpui_core/src/integration/step.rs](../../warpui_core/src/integration/step.rs).

## When to use `assert!` vs `async_assert!`
The former will fail the test the first time it's false. The latter will fail the test if we don't ever see a success in the timeout. If you don't specify a timeout, the default timeout is used.

In our UI framework, dispatching events and actions are generally synchronous. Concurrency comes mainly from the event loop.

Example of synchronous assertion:
This panicks if it fails the first time. Otherwise, it succeeds.
```rs
assert_eq!(
    view.buffer_text(ctx),
    "".to_string(),
    "Input should be empty"
);
AssertionOutcome::Success
```

Example of async assertion:
```rs
async_assert_eq!(
    expect_bootstrapped,
    bootstrapped,
    "terminal should be bootstrapped ({})",
    expect_bootstrapped
)
```

Since many of our tests are async, I would recommend running in a loop locally before merging to avoid flakes e.g.
```sh
for i in {0..100}; do
    WARPUI_USE_REAL_DISPLAY_IN_INTEGRATION_TESTS=1 RUST_BACKTRACE=full WARP_SHELL_PATH=/bin/bash cargo run -p integration -- test_simple_example
    if [ $? -ne 0 ]; then return; fi
done
```

This has helped us catch a lot of existing bugs in the system.

Note that for `async_assert` to actually work, the `set_assertion` needs to **return** with the `async_assert`.

## How to add a sqlite snapshot?
* You can copy over a warp.sqlite file from ~/Library/Application\ Support/dev.warp.WarpOss directly
* Sanitize anything specific to you (cwd, commands, user and host names), then `VACUUM` the file so deleted rows don't linger in free pages


### How to run integration tests?
To run a specific integration test you can use:
```
  WARPUI_USE_REAL_DISPLAY_IN_INTEGRATION_TESTS="1" cargo run --bin integration -- test_simple_example
```

The `WARPUI_USE_REAL_DISPLAY_IN_INTEGRATION_TESTS="1"` will force the new terminal window to open, which helps a lot when iterating on your integration test implementation!

### Waiting, retries and skips
* A step runs once and a failed step fails the test. There are no retries or reruns, neither of a step nor of a test, and CI runs nextest with `--retries 0`: a pass on a second attempt would hide a race. If a result arrives later, make the step's assertions poll for the state it needs (an assertion returns a failure until it holds, and the step fails at its timeout).
* A step's timeout is the longest the step may take, not a delay: the step ends as soon as its assertions hold. To wait for something the app does on a timer (a grace period, an expiry), assert what it does; do not sleep (`std::thread::sleep` blocks the event loop that runs the timer).
* A scenario that doesn't apply to the shell of the run (`set_should_run_test` is false) ends with its own exit code and is a skip, never a pass. The skip is printed (`OPENRUN_TEST_SKIPPED`), and it fails the test unless it is allowed: in CI by an entry in `ALLOWED_CI_SKIPS` in `tests/common/mod.rs` (with the reason), elsewhere by setting `OPENRUN_ALLOW_SKIPS=1`. Tests that need one particular shell go in the `bash_only` or `pwsh_only` module of `shell_integration_tests.rs`, are ignored by default and run in their own CI job (`WARP_SHELL_PATH=<shell> cargo nextest run -p integration --run-ignored only -E 'test(~shell_integration_tests::pwsh_only::)'`).

### Known issues / limitations
* To determine (from the `TestStep`) which shell is used for the test, you can try checking `WARP_SHELL_PATH` environment variable (that works within the CI on github) or check the passwd for the user (for local runs).
* Similarly you can run the test with a specific shell by setting the `WARP_SHELL_PATH` and then running the test. For example: `WARP_SHELL_PATH=/usr/local/bin/fish`, then `cargo run --bin integration -- test_simple_example`
* Bindings aren't exposed by default in integration tests, add them in the file of the original binding. Example from `editor/view.rs`:

```rust
if ChannelState::channel() == Channel::Integration {
        app.register_fixed_bindings([
            // Hack: Add explicit bindings for the tests, since the tests' injected
            // keypresses won't trigger Mac menu items. Unfortunately we can't use
            // cfg[test] because we are a separate process!
            Binding::new(
                "cmd-z",
                EditorAction::Undo,
                Some("EditorView && !IMEOpen")
            ),
        ]);
    }
```
