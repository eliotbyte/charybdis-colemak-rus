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
#define COMBO_MS CONFIG_ZMK_LANG_SWITCH_COMBO_MS
#define FREEZE_MS CONFIG_ZMK_LANG_SWITCH_FREEZE_MS

/*
 * Delay OS EN chord until Lower/Raise is held this long. Cancels on earlier
 * release so thumb grazes during fast RU typing don't freeze/HID-thrash.
 * Intentional symbol rolls still hit freeze once the chord arms.
 */
#define THUMB_ARM_MS 30

/* Charybdis 3x6+thumbs uses positions 0..40; keep room under 64. */
#define POS_BIT(pos) (1ULL << (pos))

/* Combo ≈ 5 + 2*COMBO_MS; keep frozen across sleeps until settle. */
#define COMBO_HOLD_MS (5 + (2 * COMBO_MS) + FREEZE_MS + 20)

static atomic_t input_frozen = ATOMIC_INIT(0);

/* Presses dropped while frozen; matching releases stay swallowed until paired. */
static uint64_t quarantined_presses;

/* Eng chord armed (delayable pending or combo running); release must restore RU. */
static atomic_t eng_armed = ATOMIC_INIT(0);

static struct k_work_delayable freeze_end_work;
static struct k_work_delayable lang_to_eng_dwork;
static struct k_work lang_to_rus_work;

/* Dedicated queue so k_msleep in lang combo does not stall system/HID work. */
K_THREAD_STACK_DEFINE(lang_switch_stack, 1536);
static struct k_work_q lang_switch_wq;

static int64_t now_ms(void) { return k_uptime_get(); }

static void keycode_set_encoded(uint32_t encoded, bool pressed) {
    raise_zmk_keycode_state_changed_from_encoded(encoded, pressed, now_ms());
}

/* Clear Shift/Alt/Gui only — keep Ctrl so RU Ctrl→Lower chords stay held on host. */
static void release_non_ctrl_modifiers(void) {
    static const uint32_t mods[] = {LSHFT, RSHFT, LALT, RALT, LGUI, RGUI};
    for (size_t i = 0; i < ARRAY_SIZE(mods); i++) {
        keycode_set_encoded(mods[i], false);
    }
}

/* Match Esc-path macros: Alt+Shift down → digit tap → mods up, with COMBO_MS gaps. */
static void send_os_lang_digit(uint32_t digit) {
    keycode_set_encoded(LALT, true);
    keycode_set_encoded(LSHFT, true);
    k_msleep(COMBO_MS);

    keycode_set_encoded(digit, true);
    keycode_set_encoded(digit, false);
    k_msleep(COMBO_MS);

    keycode_set_encoded(LSHFT, false);
    keycode_set_encoded(LALT, false);
}

static void send_os_english(void) { send_os_lang_digit(N1); }

static void send_os_russian(void) { send_os_lang_digit(N2); }

static void start_freeze_window(int hold_ms) {
    atomic_set(&input_frozen, 1);
    k_work_reschedule(&freeze_end_work, K_MSEC(hold_ms));
}

static void extend_freeze_after_combo(void) {
    atomic_set(&input_frozen, 1);
    k_work_reschedule(&freeze_end_work, K_MSEC(FREEZE_MS));
}

static void freeze_end_fn(struct k_work *work) {
    ARG_UNUSED(work);
    atomic_clear(&input_frozen);
}

static void lang_to_eng_fn(struct k_work *work) {
    ARG_UNUSED(work);
    start_freeze_window(COMBO_HOLD_MS);
    release_non_ctrl_modifiers();
    k_msleep(5);
    send_os_english();
    extend_freeze_after_combo();
}

static void lang_to_rus_fn(struct k_work *work) {
    ARG_UNUSED(work);
    release_non_ctrl_modifiers();
    k_msleep(5);
    send_os_russian();
    extend_freeze_after_combo();
    atomic_clear(&eng_armed);
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
            /* EN chord + freeze only when ZMK Russian is the base mirror. */
            if (zmk_keymap_layer_active(RUSSIAN_LAYER)) {
                atomic_set(&eng_armed, 1);
                /* Arm after THUMB_ARM_MS — grazes cancel below without freeze/HID. */
                k_work_reschedule_for_queue(&lang_switch_wq, &lang_to_eng_dwork, K_MSEC(THUMB_ARM_MS));
            }
        } else if (zmk_keymap_layer_active(RUSSIAN_LAYER)) {
            if (k_work_delayable_is_pending(&lang_to_eng_dwork)) {
                (void)k_work_cancel_delayable(&lang_to_eng_dwork);
                atomic_clear(&eng_armed);
                return ZMK_EV_EVENT_BUBBLE;
            }
            if (!atomic_get(&eng_armed)) {
                return ZMK_EV_EVENT_BUBBLE;
            }
            start_freeze_window(COMBO_HOLD_MS);
            k_work_submit_to_queue(&lang_switch_wq, &lang_to_rus_work);
        }
        return ZMK_EV_EVENT_BUBBLE;
    }

    if (ev->position >= 64) {
        return ZMK_EV_EVENT_BUBBLE;
    }

    const uint64_t bit = POS_BIT(ev->position);

    if (ev->state) {
        /* Lost release left a stale bit → would swallow this press's release (stuck HID). */
        if (quarantined_presses & bit) {
            quarantined_presses &= ~bit;
        }
        if (atomic_get(&input_frozen)) {
            quarantined_presses |= bit;
            return ZMK_EV_EVENT_HANDLED;
        }
        return ZMK_EV_EVENT_BUBBLE;
    }

    /* Release: pair with a dropped press even after freeze window ends. */
    if (quarantined_presses & bit) {
        quarantined_presses &= ~bit;
        return ZMK_EV_EVENT_HANDLED;
    }

    /* Already held before freeze — never swallow release (avoids stuck HID). */
    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(lang_switch_freeze, position_listener);
ZMK_SUBSCRIPTION(lang_switch_freeze, zmk_position_state_changed);

static int lang_switch_freeze_init(void) {
    k_work_queue_start(&lang_switch_wq, lang_switch_stack, K_THREAD_STACK_SIZEOF(lang_switch_stack),
                       K_PRIO_PREEMPT(3), NULL);
    k_thread_name_set(&lang_switch_wq.thread, "lang_sw");

    k_work_init_delayable(&freeze_end_work, freeze_end_fn);
    k_work_init_delayable(&lang_to_eng_dwork, lang_to_eng_fn);
    k_work_init(&lang_to_rus_work, lang_to_rus_fn);
    return 0;
}

SYS_INIT(lang_switch_freeze_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
