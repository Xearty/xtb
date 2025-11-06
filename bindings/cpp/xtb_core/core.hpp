#ifndef _XTB_CORE_HPP_
#define _XTB_CORE_HPP_

#include <xtb_core/core.h>

// Defer macro by gingerbill
template <typename F>
struct privDefer {
	F f;
	privDefer(F f) : f(f) {}
	~privDefer() { f(); }
};

template <typename F>
privDefer<F> defer_func(F f) {
	return privDefer<F>(f);
}

#define DEFER_1(x, y) x##y
#define DEFER_2(x, y) DEFER_1(x, y)
#define DEFER_3(x)    DEFER_2(x, __COUNTER__)
#define defer(code)   auto DEFER_3(_defer_) = defer_func([&](){code;})

void cpp_binding_function();

#endif // _XTB_CORE_HPP_
