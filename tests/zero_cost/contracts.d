module tests.zero_cost.contracts;

nothrow @nogc:

import xtb.panic : ensure, require;
import xtb.types;

enum require_message = "XTB_REQUIRE_RELEASE_FAST_SENTINEL_7A3F91D2";
enum ensure_message = "XTB_ENSURE_RELEASE_FAST_SENTINEL_4C8E20B6";

__gshared i32 condition_evaluations;
__gshared i32 message_evaluations;

private bool evaluate_condition() {
    ++condition_evaluations;
    return true;
}

private String evaluate_message(String message) {
    ++message_evaluations;
    return message;
}

extern (C) int main() {
    require(
        evaluate_condition(),
        evaluate_message(require_message),
    );
    ensure(
        evaluate_condition(),
        evaluate_message(ensure_message),
    );

    return condition_evaluations == 0 && message_evaluations == 0 ? 0 : 1;
}
