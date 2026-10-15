#include <SDL3/SDL.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
typedef struct { Uint8 *d; size_t n, cap; } B;
static void put(B*b,const void*p,size_t n){ if(b->n+n>b->cap){b->cap=(b->n+n)*2+16;b->d=realloc(b->d,b->cap);} memcpy(b->d+b->n,p,n); b->n+=n; }
static void u8(B*b,unsigned v){Uint8 x=v;put(b,&x,1);}
static void u16(B*b,unsigned v){u8(b,v&255);u8(b,(v>>8)&255);}
static void u32(B*b,unsigned v){u16(b,v&65535);u16(b,v>>16);}
static void str(B*b,const char*s){put(b,s,strlen(s));}
static void chunk(B*b,const char*id,const void*data,size_t n){str(b,id);u32(b,(unsigned)n);put(b,data,n);if(n&1)u8(b,0);}
static unsigned lcg=1; static unsigned nx(void){lcg=lcg*1103515245u+12345u;return lcg;}
static void rnd(B*b,int n){for(int i=0;i<n;i++)u8(b,nx()>>16);}
/* RIFF wrapper. riffsize<0 -> actual */
static B riff(B*body,long riffsize,const char*form){B f={0};str(&f,"RIFF");u32(&f,riffsize<0?(unsigned)(body->n+4):(unsigned)riffsize);str(&f,form);put(&f,body->d,body->n);return f;}
static B fmt_pcm(int tag,int ch,int rate,int bits,int blockalign){B b={0};u16(&b,tag);u16(&b,ch);u32(&b,rate);u32(&b,rate*blockalign);u16(&b,blockalign);u16(&b,bits);return b;}
static const short preset[14]={256,0,512,-256,0,0,192,64,240,0,460,-208,392,-232};
static B fmt_ms(int ch,int rate,int blockalign,int spb,int badcoef,int tag,int bits){B b={0};u16(&b,tag);u16(&b,ch);u32(&b,rate);u32(&b,rate*blockalign/ (spb?spb:1));u16(&b,blockalign);u16(&b,bits);u16(&b,32);u16(&b,spb);u16(&b,7);for(int i=0;i<14;i++)u16(&b,(unsigned short)(i==badcoef?preset[i]+1:preset[i]));return b;}
static B fmt_ima(int ch,int rate,int blockalign,int spb,int bits){B b={0};u16(&b,0x11);u16(&b,ch);u32(&b,rate);u32(&b,rate*blockalign/(spb?spb:1));u16(&b,blockalign);u16(&b,bits);u16(&b,2);u16(&b,spb);return b;}
static B fmt_ext(int ch,int rate,int bits,int blockalign,int sub,int extsize,int total){B b={0};u16(&b,0xFFFE);u16(&b,ch);u32(&b,rate);u32(&b,rate*blockalign);u16(&b,blockalign);u16(&b,bits);u16(&b,extsize);u16(&b,bits);u32(&b,3);
  u16(&b,sub);u16(&b,0);u32(&b,0x00100000);u32(&b,0xAA000080);u32(&b,0x719B3800); while((int)b.n<total)u8(&b,0); return b;}
static void ms_block(B*b,int ch,int total,int idxbase){ for(int c=0;c<ch;c++)u8(b,(idxbase+c)%7); for(int c=0;c<ch;c++)u16(b,16+(nx()>>20)%300); for(int c=0;c<ch;c++)u16(b,nx()>>16); for(int c=0;c<ch;c++)u16(b,nx()>>16); rnd(b,total-7*ch); }
static void ima_block(B*b,int ch,int total){ for(int c=0;c<ch;c++){u16(b,nx()>>16);u8(b,(nx()>>16)%89);u8(b,0);} rnd(b,total-4*ch); }
typedef struct { const char*name; B f; const char*r,*t,*fa,*lim; Sint64 fake; } Case;
static Case cases[200]; static int nc=0;
static void addf(const char*name,B f,const char*r,const char*t,const char*fa,const char*lim,Sint64 fake){cases[nc].name=name;cases[nc].f=f;cases[nc].r=r;cases[nc].t=t;cases[nc].fa=fa;cases[nc].lim=lim;cases[nc].fake=fake;nc++;}
static void add(const char*name,B f,const char*r,const char*t,const char*fa,const char*lim){addf(name,f,r,t,fa,lim,0);}
/* a stream whose reported size is larger than what can be read */
typedef struct {Uint8*d; size_t n; Sint64 pos; Sint64 fake;} Lie;
static Sint64 SDLCALL lie_size(void*u){return ((Lie*)u)->fake;}
static Sint64 SDLCALL lie_seek(void*u,Sint64 off,SDL_IOWhence w){Lie*l=u; Sint64 np= w==SDL_IO_SEEK_SET?off: w==SDL_IO_SEEK_CUR? l->pos+off : (Sint64)l->n+off; if(np<0)return -1; l->pos=np; return np;}
static size_t SDLCALL lie_read(void*u,void*p,size_t sz,SDL_IOStatus*st){Lie*l=u; if(l->pos>=(Sint64)l->n){*st=SDL_IO_STATUS_EOF;return 0;} size_t k=l->n-l->pos; if(k>sz)k=sz; memcpy(p,l->d+l->pos,k); l->pos+=k; if(k<sz)*st=SDL_IO_STATUS_EOF; return k;}
static size_t SDLCALL lie_write(void*u,const void*p,size_t sz,SDL_IOStatus*st){*st=SDL_IO_STATUS_ERROR;return 0;}
static bool SDLCALL lie_flush(void*u,SDL_IOStatus*st){return true;}
static bool SDLCALL lie_close(void*u){return true;}
/* WAV with a data chunk declaring declared bytes but providing only the given bytes */
static B wavshort(B*fmt,B*data,B*fact,unsigned declared){B body={0};chunk(&body,"fmt ",fmt->d,fmt->n);if(fact)chunk(&body,"fact",fact->d,fact->n);str(&body,"data");u32(&body,declared);put(&body,data->d,data->n);return riff(&body,-1,"WAVE");}
static B wav1(B*fmt,B*data,B*fact,long rs){B body={0};chunk(&body,"fmt ",fmt->d,fmt->n);if(fact)chunk(&body,"fact",fact->d,fact->n);chunk(&body,"data",data->d,data->n);return riff(&body,rs,"WAVE");}
static B fact(unsigned v){B b={0};u32(&b,v);return b;}
static unsigned fnv(const Uint8*p,Uint32 n){unsigned h=2166136261u;for(Uint32 i=0;i<n;i++){h^=p[i];h*=16777619u;}return h;}
static const char*Q(const char*s){return s?s:"";}
int main(void){
  B fm,d,fc,body;
  /* PCM */
  fm=fmt_pcm(1,1,8000,8,1); d=(B){0}; rnd(&d,11); add("pcm_u8_mono",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,2,44100,16,4); d=(B){0}; rnd(&d,28); add("pcm_s16_stereo",wav1(&fm,&d,0,-1),0,0,0,0);
  { B w=wav1(&fm,&d,0,-1); add("pcm_s16_riff_force",w,"force",0,0,0); add("pcm_s16_riff_ignore",w,"ignore",0,0,0); add("pcm_s16_riff_max",w,"maximum",0,0,0); add("pcm_s16_riff_ignorezero",w,"ignorezero",0,0,0); add("pcm_s16_riff_bogus_hint",w,"bogus",0,0,0); }
  fm=fmt_pcm(1,2,22050,24,6); d=(B){0}; rnd(&d,30); add("pcm_s24_stereo",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,1,48000,32,4); d=(B){0}; rnd(&d,20); add("pcm_s32_mono",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(3,2,44100,32,8); d=(B){0}; rnd(&d,64); fc=fact(5);
  { B w=wav1(&fm,&d,&fc,-1); add("float_fact5",w,0,0,0,0); add("float_fact5_truncate",w,0,0,"truncate",0); add("float_fact5_strict",w,0,0,"strict",0); add("float_fact5_ignore",w,0,0,"ignore",0); add("float_fact5_ignorezero",w,0,0,"ignorezero",0);
    fc=fact(0); B w0=wav1(&fm,&d,&fc,-1); add("float_fact0_ignorezero",w0,0,0,"ignorezero",0); add("float_fact0_truncate",w0,0,0,"truncate",0);
    fc=fact(500); B w1=wav1(&fm,&d,&fc,-1); add("float_fact500_truncate",w1,0,0,"truncate",0); add("float_fact500_strict",w1,0,0,"strict",0);
    B w2=wav1(&fm,&d,0,-1); add("float_nofact_strict",w2,0,0,"strict",0);
    B sh={0}; u16(&sh,1); fc=sh; B w3=wav1(&fm,&d,&fc,-1); add("float_shortfact_strict",w3,0,0,"strict",0); add("float_shortfact_truncate",w3,0,0,"truncate",0); }
  fm=fmt_pcm(3,1,44100,64,8); d=(B){0}; rnd(&d,32); add("float_64bit_err",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,1,8000,12,2); d=(B){0}; rnd(&d,8); add("pcm_12bit_err",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,2,8000,16,3); d=(B){0}; rnd(&d,12); add("pcm_blockalign_err",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,2,44100,16,4); d=(B){0}; rnd(&d,31);
  { B w=wav1(&fm,&d,0,-1); add("pcm_trailing_none",w,0,0,0,0); add("pcm_trailing_strict",w,0,"strict",0,0); add("pcm_trailing_verystrict",w,0,"verystrict",0,0); add("pcm_trailing_dropframe",w,0,"dropframe",0,0); add("pcm_trailing_dropblock",w,0,"dropblock",0,0); }
  fm=fmt_pcm(1,2,44100,16,4); d=(B){0}; add("pcm_empty",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,1,8000,16,0); d=(B){0}; rnd(&d,10); add("pcm_blockalign0",wav1(&fm,&d,0,-1),0,0,0,0);
  /* LAW */
  fm=fmt_pcm(6,1,8000,8,1); d=(B){0}; for(int i=0;i<256;i++)u8(&d,i); fc=fact(256); add("alaw_all",wav1(&fm,&d,&fc,-1),0,0,0,0); add("alaw_all_strict",wav1(&fm,&d,&fc,-1),0,0,"strict",0);
  fm=fmt_pcm(7,1,8000,8,1); add("mulaw_all",wav1(&fm,&d,&fc,-1),0,0,0,0); add("mulaw_nofact_strict",wav1(&fm,&d,0,-1),0,0,"strict",0);
  fm=fmt_pcm(7,2,8000,8,2); { B dd={0}; for(int i=0;i<51;i++)u8(&dd,i*5); add("mulaw_stereo",wav1(&fm,&dd,0,-1),0,0,0,0); add("mulaw_stereo_strict",wav1(&fm,&dd,0,-1),0,"strict",0,0); }
  fm=fmt_pcm(6,2,8000,8,1); { B dd={0}; rnd(&dd,10); add("alaw_blockalign_err",wav1(&fm,&dd,0,-1),0,0,0,0); }
  fm=fmt_pcm(6,1,8000,16,2); { B dd={0}; rnd(&dd,10); add("alaw_16bit_err",wav1(&fm,&dd,0,-1),0,0,0,0); }
  /* Extensible */
  fm=fmt_ext(2,44100,16,4,1,22,40); d=(B){0}; rnd(&d,16); add("ext_pcm16",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ext(1,44100,32,4,3,22,40); d=(B){0}; rnd(&d,16); add("ext_float",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ext(1,44100,16,2,0x55,22,40); d=(B){0}; rnd(&d,16); add("ext_mp3_guid",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ext(1,44100,16,2,1,22,36); d=(B){0}; rnd(&d,16); add("ext_short",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ext(1,44100,16,2,1,10,40); d=(B){0}; rnd(&d,16); add("ext_extsize_small",wav1(&fm,&d,0,-1),0,0,0,0);
  /* MS ADPCM */
  lcg=77; fm=fmt_ms(1,22050,20,28,-1,2,4); d=(B){0}; for(int i=0;i<2;i++)ms_block(&d,1,20,0); ms_block(&d,1,13,0);
  { B w=wav1(&fm,&d,0,-1); add("ms_mono_trail_none",w,0,0,0,0); add("ms_mono_trail_dropframe",w,0,"dropframe",0,0); add("ms_mono_trail_dropblock",w,0,"dropblock",0,0); add("ms_mono_trail_strict",w,0,"strict",0,0); add("ms_mono_trail_verystrict",w,0,"verystrict",0,0); }
  lcg=88; fm=fmt_ms(2,22050,28,16,-1,2,4); d=(B){0}; for(int i=0;i<3;i++)ms_block(&d,2,28,i); ms_block(&d,2,19,0); fc=fact(40);
  { B w=wav1(&fm,&d,&fc,-1); add("ms_stereo",w,0,0,0,0); add("ms_stereo_dropframe",w,0,"dropframe",0,0); add("ms_stereo_fact_truncate",w,0,0,"truncate",0); add("ms_stereo_fact_strict",w,0,0,"strict",0); add("ms_stereo_fact_truncate_dropframe",w,0,"dropframe","truncate",0);
    fc=fact(1000); B w2=wav1(&fm,&d,&fc,-1); add("ms_stereo_fact_too_many_strict",w2,0,0,"strict",0); add("ms_stereo_fact_too_many_truncate",w2,0,0,"truncate",0); }
  lcg=99; fm=fmt_ms(1,22050,20,0,-1,2,4); d=(B){0}; for(int i=0;i<2;i++)ms_block(&d,1,20,0); add("ms_spb0",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ms(1,22050,20,28,3,2,4); add("ms_badcoef",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ms(1,22050,20,28,-1,2,3); add("ms_bits3",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ms(3,22050,40,28,-1,2,4); add("ms_3ch",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ms(1,22050,5,28,-1,2,4); add("ms_blockalign_small",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ms(1,22050,20,40,-1,2,4); add("ms_spb_too_big",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ms(1,22050,20,1,-1,2,4); add("ms_spb1",wav1(&fm,&d,0,-1),0,0,0,0);
  { B hd={0}; lcg=5; ms_block(&hd,1,20,9); fm=fmt_ms(1,22050,20,28,-1,2,4); add("ms_coefidx_valid",wav1(&fm,&hd,0,-1),0,0,0,0); B h8={0}; ms_block(&h8,1,20,0); h8.d[0]=7; add("ms_coefidx7",wav1(&fm,&h8,0,-1),0,0,0,0); h8.d[0]=8; add("ms_coefidx8",wav1(&fm,&h8,0,-1),0,0,0,0); }
  /* IMA ADPCM */
  lcg=11; fm=fmt_ima(1,22050,16,25,4); d=(B){0}; for(int i=0;i<2;i++)ima_block(&d,1,16); ima_block(&d,1,11);
  { B w=wav1(&fm,&d,0,-1); add("ima_mono_trail_none",w,0,0,0,0); add("ima_mono_trail_dropframe",w,0,"dropframe",0,0); add("ima_mono_trail_dropblock",w,0,"dropblock",0,0); add("ima_mono_trail_strict",w,0,"strict",0,0); }
  lcg=12; fm=fmt_ima(2,22050,24,17,4); d=(B){0}; for(int i=0;i<2;i++)ima_block(&d,2,24); ima_block(&d,2,19); fc=fact(30);
  { B w=wav1(&fm,&d,&fc,-1); add("ima_stereo",w,0,0,0,0); add("ima_stereo_dropframe",w,0,"dropframe",0,0); add("ima_stereo_fact_truncate",w,0,0,"truncate",0); }
  for(int extra=5;extra<=23;extra+=2){ lcg=20+extra; fm=fmt_ima(2,22050,24,17,4); d=(B){0}; ima_block(&d,2,24); ima_block(&d,2,extra); static char nm[20][40]; static int k=0; snprintf(nm[k],40,"ima_stereo_trail%d_dropframe",extra); add(nm[k++],wav1(&fm,&d,0,-1),0,"dropframe",0,0); }
  lcg=13; fm=fmt_ima(1,22050,16,0,4); d=(B){0}; ima_block(&d,1,16); ima_block(&d,1,16); add("ima_spb0",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ima(1,22050,16,25,3); add("ima_bits3",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ima(1,22050,18,25,4); add("ima_blockalign_odd",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ima(1,22050,16,40,4); add("ima_spb_too_big",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_ima(1,22050,16,25,8); add("ima_bits8",wav1(&fm,&d,0,-1),0,0,0,0);
  /* chunk structure */
  fm=fmt_pcm(1,1,8000,16,2); d=(B){0}; rnd(&d,12);
  { B junk={0}; rnd(&junk,5); body=(B){0}; chunk(&body,"JUNK",junk.d,junk.n); chunk(&body,"fmt ",fm.d,fm.n); chunk(&body,"LIST",junk.d,3); chunk(&body,"data",d.d,d.n); chunk(&body,"cue ",junk.d,2); B f=riff(&body,-1,"WAVE"); add("chunks_junk_list",f,0,0,0,0); add("chunks_junk_list_verystrict",f,0,"verystrict",0,0);
    body=(B){0}; chunk(&body,"data",d.d,d.n); chunk(&body,"fmt ",fm.d,fm.n); f=riff(&body,-1,"WAVE"); add("data_before_fmt",f,0,0,0,0);
    body=(B){0}; chunk(&body,"data",d.d,d.n); f=riff(&body,-1,"WAVE"); add("missing_fmt",f,0,0,0,0);
    body=(B){0}; chunk(&body,"fmt ",fm.d,fm.n); f=riff(&body,-1,"WAVE"); add("missing_data",f,0,0,0,0);
    body=(B){0}; chunk(&body,"fmt ",fm.d,fm.n); chunk(&body,"fmt ",fm.d,fm.n); chunk(&body,"data",d.d,d.n); chunk(&body,"data",junk.d,4); f=riff(&body,-1,"WAVE"); add("multi_fmt_data",f,0,0,0,0);
    body=(B){0}; chunk(&body,"fmt ",fm.d,fm.n); chunk(&body,"data",d.d,d.n); f=riff(&body,0,"WAVE"); add("riff_size0",f,0,0,0,0); add("riff_size0_force",f,"force",0,0,0);
    f=riff(&body,20,"WAVE"); add("riff_size_small",f,0,0,0,0); add("riff_size_small_force",f,"force",0,0,0); add("riff_size_small_ignore",f,"ignore",0,0,0); add("riff_size_small_verystrict",f,0,"verystrict","",0); add("riff_size_small_force_verystrict",f,"force","verystrict",0,0);
    f=riff(&body,-1,"AVI "); add("form_not_wave",f,0,0,0,0);
    B nr={0}; str(&nr,"WAVE"); put(&nr,body.d,body.n); add("no_riff_header",nr,0,0,0,0);
    B bad={0}; str(&bad,"XXXXabcdefgh"); add("bad_magic",bad,0,0,0,0);
    B tiny={0}; str(&tiny,"RIF"); add("tiny",tiny,0,0,0,0);
    B hdr={0}; str(&hdr,"RIFF"); u32(&hdr,4); add("riff_no_form",hdr,0,0,0,0);
    /* data length larger than file */
    B big={0}; str(&big,"fmt "); u32(&big,fm.n); put(&big,fm.d,fm.n); str(&big,"data"); u32(&big,1000); put(&big,d.d,d.n); f=riff(&big,-1,"WAVE"); add("data_len_over",f,0,0,0,0); add("data_len_over_strict",f,0,"strict",0,0); add("data_len_over_verystrict",f,0,"verystrict",0,0);
    /* trailing chunk truncated */
    B tr={0}; str(&tr,"fmt "); u32(&tr,fm.n); put(&tr,fm.d,fm.n); chunk(&tr,"data",d.d,d.n); str(&tr,"LIST"); u32(&tr,100); rnd(&tr,10); f=riff(&tr,-1,"WAVE"); add("trailing_trunc_chunk",f,0,0,0,0); add("trailing_trunc_chunk_verystrict",f,0,"verystrict",0,0);
    B tr2={0}; str(&tr2,"fmt "); u32(&tr2,fm.n); put(&tr2,fm.d,fm.n); chunk(&tr2,"data",d.d,d.n); str(&tr2,"LI"); f=riff(&tr2,-1,"WAVE"); add("trailing_partial_header",f,0,0,0,0); add("trailing_partial_header_verystrict",f,0,"verystrict",0,0);
    /* seek beyond the end (SDL's memory stream clamps, so the seek fails) */
    B hug={0}; str(&hug,"fmt "); u32(&hug,fm.n); put(&hug,fm.d,fm.n); str(&hug,"JUNK"); u32(&hug,1000); rnd(&hug,4); f=riff(&hug,-1,"WAVE"); add("junk_len_huge",f,0,0,0,0); add("junk_len_huge_verystrict",f,0,"verystrict",0,0); add("junk_len_huge_strict",f,0,"strict",0,0); add("junk_len_huge_ignore",f,"ignore",0,0,0); add("junk_len_huge_ignore_verystrict",f,"ignore","verystrict",0,0); add("junk_len_huge_maximum",f,"maximum",0,0,0);
    B hf={0}; str(&hf,"fmt "); u32(&hf,1000); put(&hf,fm.d,fm.n); f=riff(&hf,-1,"WAVE"); add("fmt_len_huge",f,0,0,0,0); add("fmt_len_huge_ignore",f,"ignore",0,0,0);
    /* many chunks */
    B many={0}; chunk(&many,"fmt ",fm.d,fm.n); for(int i=0;i<20;i++)chunk(&many,"JUNK",junk.d,4); chunk(&many,"data",d.d,d.n); f=riff(&many,-1,"WAVE"); add("chunks_many",f,0,0,0,0); add("chunks_many_limit5",f,0,0,0,"5"); add("chunks_many_limit21",f,0,0,0,"21"); add("chunks_many_limit22",f,0,0,0,"22"); add("chunks_many_limit_abc",f,0,0,0,"abc"); add("chunks_many_limit0",f,0,0,0,"0"); }
  /* format checks */
  fm=fmt_pcm(1,0,8000,16,2); d=(B){0}; rnd(&d,8); add("channels0",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,1,0,16,2); add("freq0",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,1,0x80000000u,16,2); add("freq_huge",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(1,1,8000,0,2); add("bits0",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(0x50,1,8000,16,2); add("mpeg_tag",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(0x55,1,8000,16,2); add("mp3_tag",wav1(&fm,&d,0,-1),0,0,0,0);
  fm=fmt_pcm(0x1234,1,8000,16,2); add("unknown_tag",wav1(&fm,&d,0,-1),0,0,0,0);
  { B s={0}; rnd(&s,10); body=(B){0}; chunk(&body,"fmt ",s.d,10); chunk(&body,"data",d.d,d.n); B f=riff(&body,-1,"WAVE"); add("fmt_len10",f,0,0,0,0);
    B s14={0}; u16(&s14,1);u16(&s14,1);u32(&s14,8000);u32(&s14,16000);u16(&s14,2); body=(B){0}; chunk(&body,"fmt ",s14.d,s14.n); chunk(&body,"data",d.d,d.n); f=riff(&body,-1,"WAVE"); add("fmt_len14_pcm",f,0,0,0,0);
    B s14f={0}; u16(&s14f,3);u16(&s14f,1);u32(&s14f,8000);u32(&s14f,16000);u16(&s14f,2); body=(B){0}; chunk(&body,"fmt ",s14f.d,s14f.n); chunk(&body,"data",d.d,d.n); f=riff(&body,-1,"WAVE"); add("fmt_len14_float",f,0,0,0,0); }
  /* IMA step index byte >= 0x80 */
  lcg=31; fm=fmt_ima(1,22050,16,25,4); { B x={0}; for(int i=0;i<3;i++){ ima_block(&x,1,16); } 
    x.d[2]=0xF0; x.d[18]=0x80; x.d[34]=0x81; add("ima_stepidx_high",wav1(&fm,&x,0,-1),0,0,0,0); x.d[2]=0xFF; x.d[18]=0x7F; add("ima_stepidx_ff_7f",wav1(&fm,&x,0,-1),0,0,0,0); }
  /* streams that lie about their size: data shorter than declared */
  fm=fmt_pcm(1,2,44100,16,4); { B x={0}; rnd(&x,31); B w=wavshort(&fm,&x,0,100); const char*hs[]={0,"strict","verystrict","dropframe","dropblock"}; static char nmx[40][40]; static int kx=0; for(int h=0;h<5;h++){ snprintf(nmx[kx],40,"short_pcm_%s",hs[h]?hs[h]:"none"); addf(nmx[kx++],w,0,hs[h],0,0,4096);} }
  fm=fmt_pcm(7,1,8000,8,1); { B x={0}; rnd(&x,20); fc=fact(100); B w=wavshort(&fm,&x,&fc,100); addf("short_mulaw",w,0,0,0,0,4096); addf("short_mulaw_truncate",w,0,0,"truncate",0,4096); addf("short_mulaw_strict",w,0,"strict","strict",0,4096); }
  fm=fmt_pcm(3,1,44100,32,4); { B x={0}; rnd(&x,22); fc=fact(50); B w=wavshort(&fm,&x,&fc,200); addf("short_float",w,0,0,0,0,4096); addf("short_float_truncate",w,0,0,"truncate",0,4096); }
  fm=fmt_pcm(1,1,8000,24,3); { B x={0}; rnd(&x,10); B w=wavshort(&fm,&x,0,30); addf("short_pcm24",w,0,0,0,0,4096); }
  lcg=41; fm=fmt_ms(1,22050,20,28,-1,2,4); { B x={0}; ms_block(&x,1,20,0); ms_block(&x,1,13,0); B w=wavshort(&fm,&x,0,100); const char*hs[]={0,"strict","verystrict","dropframe","dropblock"}; static char nmm[40][40]; static int km=0; for(int h=0;h<5;h++){ snprintf(nmm[km],40,"short_ms_mono_%s",hs[h]?hs[h]:"none"); addf(nmm[km++],w,0,hs[h],0,0,4096);} }
  lcg=42; fm=fmt_ms(2,22050,28,16,-1,2,4); { B x={0}; ms_block(&x,2,28,0); ms_block(&x,2,28,1); ms_block(&x,2,17,2); B w=wavshort(&fm,&x,0,200); const char*hs[]={0,"dropframe","dropblock"}; static char nms[40][40]; static int ks=0; for(int h=0;h<3;h++){ snprintf(nms[ks],40,"short_ms_stereo_%s",hs[h]?hs[h]:"none"); addf(nms[ks++],w,0,hs[h],0,0,4096);} }
  lcg=43; fm=fmt_ima(1,22050,16,25,4); { B x={0}; ima_block(&x,1,16); ima_block(&x,1,9); B w=wavshort(&fm,&x,0,100); const char*hs[]={0,"strict","verystrict","dropframe","dropblock"}; static char nmi[40][40]; static int ki=0; for(int h=0;h<5;h++){ snprintf(nmi[ki],40,"short_ima_mono_%s",hs[h]?hs[h]:"none"); addf(nmi[ki++],w,0,hs[h],0,0,4096);} }
  for(int extra=5;extra<=23;extra+=3){ lcg=50+extra; fm=fmt_ima(2,22050,24,17,4); B x={0}; ima_block(&x,2,24); ima_block(&x,2,extra); B w=wavshort(&fm,&x,0,100); static char nmj[20][40]; static int kj=0; snprintf(nmj[kj],40,"short_ima_stereo_trail%d_dropframe",extra); addf(nmj[kj++],w,0,"dropframe",0,0,4096); snprintf(nmj[kj],40,"short_ima_stereo_trail%d_none",extra); addf(nmj[kj++],w,0,0,0,0,4096); }
  /* output */
  for(int i=0;i<nc;i++){
    Case*c=&cases[i];
    SDL_ResetHints();
    SDL_SetHint("SDL_WAVE_RIFF_CHUNK_SIZE",c->r&&*c->r?c->r:NULL); SDL_SetHint("SDL_WAVE_TRUNCATION",c->t&&*c->t?c->t:NULL); SDL_SetHint("SDL_WAVE_FACT_CHUNK",c->fa&&*c->fa?c->fa:NULL); SDL_SetHint("SDL_WAVE_CHUNK_LIMIT",c->lim);
    Lie lie={c->f.d,c->f.n,0,c->fake}; SDL_IOStreamInterface ifc; SDL_INIT_INTERFACE(&ifc); ifc.size=lie_size; ifc.seek=lie_seek; ifc.read=lie_read; ifc.write=lie_write; ifc.flush=lie_flush; ifc.close=lie_close;
    SDL_IOStream*io=c->fake?SDL_OpenIO(&ifc,&lie):SDL_IOFromConstMem(c->f.d,c->f.n);
    SDL_AudioSpec sp; Uint8*buf=NULL; Uint32 len=0;
    SDL_ClearError();
    bool ok=SDL_LoadWAV_IO(io,false,&sp,&buf,&len);
    printf("  (N: '%s'; R: '%s'; T: '%s'; F: '%s'; L: '%s'; Fake: %lld; Hex: '",c->name,Q(c->r),Q(c->t),Q(c->fa),Q(c->lim),(long long)c->fake);
    for(size_t k=0;k<c->f.n;k++)printf("%02X",c->f.d[k]);
    if(ok) printf("'; Err: ''; Fmt: $%04X; Ch: %d; Freq: %d; Len: %u; Hash: $%08X; Pos: %lld),\n",sp.format,sp.channels,sp.freq,len,fnv(buf,len),(long long)SDL_TellIO(io));
    else printf("'; Err: '%s'; Fmt: 0; Ch: 0; Freq: 0; Len: 0; Hash: 0; Pos: 0),\n",SDL_GetError());
    SDL_free(buf); SDL_CloseIO(io);
  }
  fprintf(stderr,"%d cases\n",nc);
  return 0;}
