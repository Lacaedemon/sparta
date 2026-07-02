extends GutTest
## Unit tests for RunWatchdog's pure helpers: the wall-clock expiry decision and
## the env-var budget parse. The node's quit path can't run under GUT (it would
## kill the test process), so the decision logic is static and pinned here.


func test_expired_just_under_budget() -> void:
	assert_false(RunWatchdog.expired(0, 899_999, 900.0))


func test_expired_exactly_at_budget() -> void:
	assert_true(RunWatchdog.expired(0, 900_000, 900.0))


func test_expired_past_budget() -> void:
	assert_true(RunWatchdog.expired(1_000, 950_000, 900.0))


func test_expired_measures_from_start_not_zero() -> void:
	# 899.999s elapsed relative to a non-zero start: still inside the budget.
	assert_false(RunWatchdog.expired(500_000, 1_399_999, 900.0))


func test_timeout_from_env_empty_uses_default() -> void:
	assert_eq(RunWatchdog.timeout_from_env("", 900.0), 900.0)


func test_timeout_from_env_valid_value_overrides() -> void:
	assert_eq(RunWatchdog.timeout_from_env("120", 900.0), 120.0)


func test_timeout_from_env_fractional_value_overrides() -> void:
	assert_eq(RunWatchdog.timeout_from_env("0.5", 900.0), 0.5)


func test_timeout_from_env_garbage_uses_default() -> void:
	assert_eq(RunWatchdog.timeout_from_env("soon", 900.0), 900.0)


func test_timeout_from_env_zero_uses_default() -> void:
	assert_eq(RunWatchdog.timeout_from_env("0", 900.0), 900.0)


func test_timeout_from_env_negative_uses_default() -> void:
	assert_eq(RunWatchdog.timeout_from_env("-5", 900.0), 900.0)


func test_create_returns_configured_node() -> void:
	var dog: RunWatchdog = autofree(RunWatchdog.create("test run"))
	assert_eq(str(dog.name), "RunWatchdog")
	assert_eq(dog.run_label, "test run")
	assert_gt(dog.timeout_sec, 0.0)
