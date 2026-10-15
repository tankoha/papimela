/* SDL の ALSA ドライバが、この機械のデバイスをどう列挙し、どう開くかを書き出す（papimela の
   test_audio_alsa が実行時に動かして、papimela のバックエンドと突き合わせる）。
   使い方: sdl_alsa_probe   （システムの libSDL3 に直接リンクして作る。test が作る）
   出力（1 行ずつ）:
     D <P|R> <名前>                         列挙されたデバイス
     O <P|R> <名前> <求めた仕様> -> <形式> <チャンネル数> <周波数> <フレーム数> <並び> | ERR <文面>
   音は鳴らさない（開いて、仕様を読んで、閉じるだけ。再生のデバイスには SDL が無音を流す）。 */
#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>

static const char *fmtname(SDL_AudioFormat f) {
  switch (f) { case SDL_AUDIO_U8: return "U8"; case SDL_AUDIO_S8: return "S8";
    case SDL_AUDIO_S16LE: return "S16LE"; case SDL_AUDIO_S16BE: return "S16BE";
    case SDL_AUDIO_S32LE: return "S32LE"; case SDL_AUDIO_S32BE: return "S32BE";
    case SDL_AUDIO_F32LE: return "F32LE"; case SDL_AUDIO_F32BE: return "F32BE"; default: return "UNKNOWN"; }
}

int main(void) {
  SDL_SetHint("SDL_AUDIO_DRIVER", "alsa");
  if (!SDL_Init(SDL_INIT_AUDIO)) { printf("INIT-ERR %s\n", SDL_GetError()); return 1; }
  if (strcmp(SDL_GetCurrentAudioDriver(), "alsa") != 0) { printf("INIT-ERR driver %s\n", SDL_GetCurrentAudioDriver()); return 1; }
  static const struct { SDL_AudioFormat f; int ch, freq; } wants[] = {
    { SDL_AUDIO_F32LE, 2, 48000 }, { SDL_AUDIO_S16LE, 2, 44100 }, { SDL_AUDIO_S16LE, 6, 48000 },
    { SDL_AUDIO_U8, 1, 22050 }, { SDL_AUDIO_F32LE, 8, 48000 }, { SDL_AUDIO_S32LE, 2, 96000 }, { SDL_AUDIO_S8, 4, 32000 } };
  for (int dir = 0; dir < 2; dir++) {
    int n = 0;
    SDL_AudioDeviceID *ids = dir == 0 ? SDL_GetAudioPlaybackDevices(&n) : SDL_GetAudioRecordingDevices(&n);
    for (int i = 0; i < n; i++) printf("D %c %s\n", dir == 0 ? 'P' : 'R', SDL_GetAudioDeviceName(ids[i]));
    /* 録音は開かない（マイクを勝手に開かない）。再生だけ開く */
    if (dir == 0) {
      for (int i = 0; i < n; i++) {
        for (unsigned w = 0; w < sizeof(wants) / sizeof(wants[0]); w++) {
          SDL_AudioSpec want = { wants[w].f, wants[w].ch, wants[w].freq };
          SDL_AudioDeviceID d = SDL_OpenAudioDevice(ids[i], &want);
          printf("O P %s %s,%d,%d -> ", SDL_GetAudioDeviceName(ids[i]), fmtname(wants[w].f), wants[w].ch, wants[w].freq);
          if (!d) { printf("ERR %s\n", SDL_GetError()); continue; }
          SDL_AudioSpec got; int frames = 0;
          if (!SDL_GetAudioDeviceFormat(d, &got, &frames)) { printf("ERR(format) %s\n", SDL_GetError()); SDL_CloseAudioDevice(d); continue; }
          int cm = 0; int *map = SDL_GetAudioDeviceChannelMap(d, &cm);
          printf("%s %d %d %d ", fmtname(got.format), got.channels, got.freq, frames);
          if (map) { for (int k = 0; k < cm; k++) printf("%s%d", k ? "," : "", map[k]); SDL_free(map); } else printf("-");
          printf("\n");
          SDL_CloseAudioDevice(d);
        }
      }
    }
    SDL_free(ids);
  }
  SDL_Quit();
  return 0;
}
