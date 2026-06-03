#include <zephyr/kernel.h>
#include <zephyr/sys/atomic.h>
#include <zmk/event_manager.h>
#include <zmk/events/position_state_changed.h>
#include <zmk/events/keycode_state_changed.h>
#include <zmk/keymap.h>
#include <dt-bindings/zmk/keys.h>

#define LOWER_POS CONFIG_ZMK_LANG_SWITCH_LOWER_POS
#define RAISE_POS CONFIG_ZMK_LANG_SWITCH_RAISE_POS
#define RUSSIAN_LAYER CONFIG_ZMK_LANG_SWITCH_RUSSIAN_LAYER

static atomic_t input_frozen = ATOMIC_INIT(0);

static struct k_work_delayable freeze_end_work;
static struct k_work lang_to_eng_work;
static struct k_work lang_to_rus_work;

static int64_t now_ms(void) { return k_uptime_get(); }

static void keycode_release_encoded(uint32_t encoded) {
    raise_zmk_keycode_state_changed_from_encoded(encoded, false, now_ms());
}

static void release_all_modifiers(void) {
    static const uint32_t mods[] = {LSHFT, RSHFT, LCTRL, RCTRL, LALT, RALT, LGUI, RGUI};
    for (size_t i = 0; i < ARRAY_SIZE(mods); i++) {
        keycode_release_encoded(mods[i]);
    }
}

static void tap_lang_combo(uint32_t encoded) {
    int64_t t = now_ms();
    raise_zmk_keycode_state_changed_from_encoded(encoded, true, t);
    raise_zmk_keycode_state_changed_from_encoded(encoded, false, now_ms());
}

static void send_os_english(void) { tap_lang_combo(LA(LS(N1))); }

static void send_os_russian(void) { tap_lang_combo(LA(LS(N2))); }

static void freeze_end_fn(struct k_work *work) { atomic_clear(&input_frozen); }

static void lang_to_eng_fn(struct k_work *work) {
    release_all_modifiers();
    k_msleep(5);
    send_os_english();
}

static void lang_to_rus_fn(struct k_work *work) {
    release_all_modifiers();
    k_msleep(5);
    send_os_russian();
}

static void start_freeze_window(void) {
    atomic_set(&input_frozen, 1);
    k_work_reschedule(&freeze_end_work, K_MSEC(CONFIG_ZMK_LANG_SWITCH_FREEZE_MS));
}

static bool is_layer_thumb(uint32_t position) {
    return position == LOWER_POS || position == RAISE_POS;
}

static int position_listener(const zmk_event_t *eh) {
    const struct zmk_position_state_changed *ev = as_zmk_position_state_changed(eh);
    if (ev == NULL) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    if (is_layer_thumb(ev->position)) {
        if (ev->state) {
            start_freeze_window();
            k_work_submit(&lang_to_eng_work);
        } else if (zmk_keymap_layer_active(RUSSIAN_LAYER)) {
            start_freeze_window();
            k_work_submit(&lang_to_rus_work);
        }
        return ZMK_EV_EVENT_BUBBLE;
    }

    if (atomic_get(&input_frozen)) {
        return ZMK_EV_EVENT_HANDLED;
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(lang_switch_freeze, position_listener);
ZMK_SUBSCRIPTION(lang_switch_freeze, zmk_position_state_changed);

static int lang_switch_freeze_init(void) {
    k_work_init_delayable(&freeze_end_work, freeze_end_fn);
    k_work_init(&lang_to_eng_work, lang_to_eng_fn);
    k_work_init(&lang_to_rus_work, lang_to_rus_fn);
    return 0;
}

SYS_INIT(lang_switch_freeze_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
