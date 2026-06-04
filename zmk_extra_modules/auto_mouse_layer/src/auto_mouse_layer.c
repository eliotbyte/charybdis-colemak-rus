#include <zephyr/kernel.h>
#include <zephyr/input/input.h>
#include <zmk/event_manager.h>
#include <zmk/events/keycode_state_changed.h>
#include <zmk/keymap.h>

/* Must match layer indices in config/charybdis.keymap (0-based declaration order). */
#define MOUSE_LAYER 2
#define GAME_LAYER 10
#define GAME_LOWER_LAYER 11

static bool game_mode_active(void) {
    return zmk_keymap_layer_active(GAME_LAYER) || zmk_keymap_layer_active(GAME_LOWER_LAYER);
}

static atomic_t mouse_active  = ATOMIC_INIT(0);
static atomic_t keyboard_lock = ATOMIC_INIT(0);

static struct k_work_delayable mouse_timeout_work;
static struct k_work_delayable keyboard_lock_work;
static struct k_work_delayable activate_mouse_work;

static void mouse_timeout_fn(struct k_work *work) {
    atomic_clear(&mouse_active);
    zmk_keymap_layer_deactivate(MOUSE_LAYER, false);
}

static void keyboard_lock_fn(struct k_work *work) {
    atomic_clear(&keyboard_lock);
}

static void activate_mouse_fn(struct k_work *work) {
    if (game_mode_active()) return;
    if (atomic_get(&keyboard_lock)) return;
    if (!atomic_get(&mouse_active)) {
        atomic_set(&mouse_active, 1);
        zmk_keymap_layer_activate(MOUSE_LAYER, false);
    }
    k_work_reschedule(&mouse_timeout_work, K_MSEC(CONFIG_ZMK_AUTO_MOUSE_TIMEOUT_MS));
}

static void trackball_input_cb(struct input_event *evt, void *user_data) {
    if (evt->type == INPUT_EV_REL &&
        (evt->code == INPUT_REL_X || evt->code == INPUT_REL_Y)) {
        k_work_reschedule(&activate_mouse_work, K_NO_WAIT);
    }
}
INPUT_CALLBACK_DEFINE(NULL, trackball_input_cb, NULL);

static int keycode_listener_cb(const zmk_event_t *eh) {
    const struct zmk_keycode_state_changed *ev = as_zmk_keycode_state_changed(eh);
    if (!ev || !ev->state) return ZMK_EV_EVENT_BUBBLE;

    if (game_mode_active()) return ZMK_EV_EVENT_BUBBLE;

    if (atomic_get(&mouse_active)) {
        k_work_reschedule(&mouse_timeout_work, K_MSEC(CONFIG_ZMK_AUTO_MOUSE_TIMEOUT_MS));
    } else {
        atomic_set(&keyboard_lock, 1);
        k_work_reschedule(&keyboard_lock_work, K_MSEC(CONFIG_ZMK_AUTO_MOUSE_KB_LOCK_MS));
    }
    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(auto_mouse_keycode_listener, keycode_listener_cb);
ZMK_SUBSCRIPTION(auto_mouse_keycode_listener, zmk_keycode_state_changed);

static int auto_mouse_init(void) {
    k_work_init_delayable(&mouse_timeout_work, mouse_timeout_fn);
    k_work_init_delayable(&keyboard_lock_work, keyboard_lock_fn);
    k_work_init_delayable(&activate_mouse_work, activate_mouse_fn);
    return 0;
}

SYS_INIT(auto_mouse_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
