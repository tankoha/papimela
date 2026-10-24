/*
 * haptic_suspects.c — SDL のハプティクスの「読んだだけの疑い」を、SDL 自身のコードで確かめる使い捨ての検証。
 *
 * 実機の FF 機器が無いので、libc の open / fstat / ioctl をこのプログラムで差し替えて、偽の FF 機器
 * （/dev/input/event3。FF_RUMBLE だけ持つ、BTN_MOUSE の無い機器）を SDL に見せる。SDL のコード
 * （SDL_Init(SDL_INIT_HAPTIC) 以降）は静的に作った参照版そのままで、差し替えたのは OS の窓口だけ。
 *
 * 使い方（tools/haptic-expect/gen.bb と同じ、静的に作った参照版 SDL。HAPTIC が有効なもの）:
 *   cc -O1 -w -Ireference/SDL/include tools/haptic-expect/haptic_suspects.c -o /tmp/hs \
 *      <ビルドの場所>/libSDL3.a -lm -lpthread -ldl && /tmp/hs
 *
 * 確かめること:
 *   S1  SDL_IsMouseHaptic: BTN_MOUSE の無い機器でも true になるか（EV_IsMouse の戻りが常に true）
 *   S2  SDL_OpenHapticFromMouse: 添字を ID として SDL_OpenHaptic に渡して失敗するか
 *   S3  機器が開けないとき SDL_IsMouseHaptic が true になるか（SDL_SetError の戻り値 false が添字 0 になる）
 *   S4  作っていない効果の SDL_RunHapticEffect / SDL_StopHapticEffect / SDL_UpdateHapticEffect で落ちるか
 */
#define _GNU_SOURCE
#include <SDL3/SDL.h>
#include <linux/input.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
#include <unistd.h>

#define FAKE_PATH "/dev/input/event3"
#define MAX_FAKE 64

static int fake_fd[MAX_FAKE];
static int fake_count = 0;
static int fail_open = 0;      /* 1 のとき、偽の機器を開こうとすると失敗する */

static int is_fake_fd(int fd)
{
    int i;
    for (i = 0; i < fake_count; i++) {
        if (fake_fd[i] == fd) return 1;
    }
    return 0;
}

static int do_open(const char *path, int flags, mode_t mode)
{
    if (path && strcmp(path, FAKE_PATH) == 0) {
        int fd;
        if (fail_open) return -1;
        fd = (int)syscall(SYS_openat, AT_FDCWD, "/dev/null", O_RDWR | O_CLOEXEC, 0);
        if (fd >= 0 && fake_count < MAX_FAKE) fake_fd[fake_count++] = fd;
        return fd;
    }
    return (int)syscall(SYS_openat, AT_FDCWD, path, flags, mode);
}
int open(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return do_open(path, flags, mode);
}
int open64(const char *path, int flags, ...)
{
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return do_open(path, flags, mode);
}

int fstat(int fd, struct stat *st)
{
    int r = (int)syscall(SYS_fstat, fd, st);
    if (r == 0 && is_fake_fd(fd)) {
        st->st_rdev = makedev(13, 67);       /* event3 */
        st->st_mode = (st->st_mode & ~S_IFMT) | S_IFCHR;
    }
    return r;
}

int ioctl(int fd, unsigned long req, ...)
{
    va_list ap;
    void *arg;
    va_start(ap, req);
    arg = va_arg(ap, void *);
    va_end(ap);
    if (is_fake_fd(fd)) {
        unsigned nr = _IOC_NR(req), size = _IOC_SIZE(req);
        if (_IOC_TYPE(req) == 'E' && nr >= 0x20 && nr < 0x40) {
            /* EVIOCGBIT(ev, len) */
            unsigned ev = nr - 0x20;
            memset(arg, 0, size);
            if (ev == EV_FF) {
                ((unsigned char *)arg)[FF_RUMBLE / 8] |= 1 << (FF_RUMBLE % 8);
            }
            return 0;
        }
        if (_IOC_TYPE(req) == 'E' && nr == 0x06) {
            /* EVIOCGNAME */
            snprintf((char *)arg, size, "Fake Rumble Device");
            return (int)strlen((char *)arg) + 1;
        }
        if (req == EVIOCGEFFECTS) {
            *(int *)arg = 8;
            return 0;
        }
        return 0;
    }
    return (int)syscall(SYS_ioctl, fd, req, arg);
}

/* SDL の内部の構造体（src/haptic/SDL_syshaptic.h の写し。S4 の準備だけに使う） */
struct haptic_effect_ { SDL_HapticEffect effect; void *hweffect; };
struct haptic_ {
    SDL_HapticID instance_id; char *name; struct haptic_effect_ *effects; int neffects; int nplaying;
    Uint32 supported; int naxes; void *hwdata; int ref_count; SDL_HapticEffectID rumble_id;
    SDL_HapticEffect rumble_effect; void *next;
};

static int child_signal(int (*fn)(SDL_Haptic *), SDL_Haptic *h)
{
    pid_t pid = fork();
    int status = 0;
    if (pid == 0) {
        fn(h);
        _exit(0);
    }
    waitpid(pid, &status, 0);
    if (WIFSIGNALED(status)) return WTERMSIG(status);
    return 0;
}

static int run_unallocated(SDL_Haptic *h) { return SDL_RunHapticEffect(h, 0, 1); }
static int stop_unallocated(SDL_Haptic *h) { return SDL_StopHapticEffect(h, 0); }
static int update_unallocated(SDL_Haptic *h)
{
    SDL_HapticEffect e;
    memset(&e, 0, sizeof(e));
    e.type = SDL_HAPTIC_LEFTRIGHT;
    return SDL_UpdateHapticEffect(h, 0, &e);
}

int main(void)
{
    int count = 0;
    SDL_HapticID *ids;
    SDL_Haptic *h, *m;
    int sig;

    if (!SDL_Init(SDL_INIT_HAPTIC)) {
        printf("INIT-ERR %s\n", SDL_GetError());
        return 1;
    }
    ids = SDL_GetHaptics(&count);
    printf("haptics: %d (id %u)\n", count, count > 0 ? (unsigned)ids[0] : 0u);
    if (count < 1) {
        printf("偽の機器が見えない\n");
        return 1;
    }

    /* S1 */
    printf("S1 SDL_IsMouseHaptic (BTN_MOUSE の無い機器だけ) = %d\n", SDL_IsMouseHaptic() ? 1 : 0);

    /* S2 */
    SDL_ClearError();
    m = SDL_OpenHapticFromMouse();
    printf("S2 SDL_OpenHapticFromMouse = %s (error: \"%s\")\n", m ? "opened" : "NULL", SDL_GetError());
    if (m) SDL_CloseHaptic(m);
    printf("   （比較: SDL_OpenHaptic(%u) = %s）\n", (unsigned)ids[0], (m = SDL_OpenHaptic(ids[0])) ? "opened" : "NULL");
    if (m) SDL_CloseHaptic(m);

    /* S3 */
    fail_open = 1;
    printf("S3 機器が開けないとき SDL_IsMouseHaptic = %d\n", SDL_IsMouseHaptic() ? 1 : 0);
    fail_open = 0;

    /* S4 */
    h = SDL_OpenHaptic(ids[0]);
    if (!h) {
        printf("S4 開けない: %s\n", SDL_GetError());
        return 1;
    }
    printf("S4 neffects = %d\n", SDL_GetMaxHapticEffects(h));
    sig = child_signal(run_unallocated, h);
    printf("S4 作っていない効果の SDL_RunHapticEffect: シグナル %d%s\n", sig, sig == 11 ? " (SIGSEGV)" : "");
    sig = child_signal(stop_unallocated, h);
    printf("S4 作っていない効果の SDL_StopHapticEffect: シグナル %d%s\n", sig, sig == 11 ? " (SIGSEGV)" : "");
    sig = child_signal(update_unallocated, h);
    printf("S4 作っていない効果の SDL_UpdateHapticEffect: シグナル %d%s\n", sig, sig == 11 ? " (SIGSEGV)" : "");
    SDL_CloseHaptic(h);
    SDL_free(ids);
    SDL_Quit();
    return 0;
}
