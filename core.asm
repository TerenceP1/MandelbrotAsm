.data
ALIGN 16               ; YMM requires 32-byte alignment
consecutive REAL4 0.0,1.0,2.0,3.0,4.0,5.0,6.0,7.0
consecutive2 REAL8 0.0,1.0,2.0,3.0
float8 REAL4 8.0
four REAL4 4.0 
float8d REAL8 8.0
fourd REAL8 4.0 
_256f REAL4 256.0
_256d REAL8 256.0
mask2 DWORD 8 DUP(0FFh)
align 16
lowbyte_mask BYTE 0, 4, 8, 12, \
                   080h, 080h, 080h, 080h, \
                   080h, 080h, 080h, 080h, \
                   080h, 080h, 080h, 080h
lowbyte_mask_d BYTE 0, 8, 080h, 080h, \
                   080h, 080h, 080h, 080h, \
                   080h, 080h, 080h, 080h, \
                   080h, 080h, 080h, 080h

EXTERN printf:PROC
msg db "Checkpoint 1 reached", 0Ah, 0  ; 0Ah = newline, 0 = null-terminator
msg2 db "Checkpoint 2 reached", 0Ah, 0  ; 0Ah = newline, 0 = null-terminator
msg3 db "Checkpoint 3 reached", 0Ah, 0  ; 0Ah = newline, 0 = null-terminator
.code

PUBLIC AddFloats           ; <-- MUST do this

AddFloats PROC ; just a tester
    ; XMM0 = first float, XMM1 = second float
    addss xmm0, xmm1       ; add floats
    ret                    ; return, result in XMM0
AddFloats ENDP

MakeRowFloat PROC ; single fp version using AVX256
; first parameter is re xmm0, secons is im xmm1, third is step length xmm2, fourth is max iteration, 5th is spectrum length (last 2 ints), 6th is pointer to H, 7th is pointer to V (s always 1)


; patching a stupid mistake when reading the x64 ABI (aka interweave because why change the code the loop uses everything)
mov rcx,r9
mov edx,dword ptr [rsp+40]
mov r8,qword ptr [rsp+48]
mov r9,qword ptr [rsp+56]
;sub rsp, 8
push rbx

; nonvolitile preservation :( ABI stuff
sub rsp, 7*16         ; reserve 112 bytes for XMM6–XMM12

vmovaps [rsp + 0*16], xmm6
vmovaps [rsp + 1*16], xmm7
vmovaps [rsp + 2*16], xmm8
vmovaps [rsp + 3*16], xmm9
vmovaps [rsp + 4*16], xmm10
vmovaps [rsp + 5*16], xmm11
vmovaps [rsp + 6*16], xmm12


; preperation


vbroadcastss ymm3,xmm2 ; to change incrments
vbroadcastss ymm2,xmm1 ; the im is row, doesnt change
vbroadcastss ymm1,xmm0 ; this is re
; adding increments
vmovups ymm0,consecutive
vmulps ymm0,ymm0,ymm3
vaddps ymm1,ymm1,ymm0 ; add consecutive increments
; increment for the column each set
movss xmm4,float8
vbroadcastss ymm4,xmm4 ; ymm4 is now dedicated to incrementing ymm1
vmulps ymm4,ymm4,ymm3
cvtsi2ss xmm0, rdx
vbroadcastss ymm13, xmm0 
cvtsi2ss xmm0, rcx
vbroadcastss ymm14, xmm0 
vbroadcastss ymm0,four
; --- Save registers on stack ---
;push rcx
;push rdx

; --- Call printf (stack already aligned with sub rsp,8 done earlier) ---
;lea rcx, msg       ; RCX = pointer to string
;xor rdx, rdx       ; no additional args
;call printf

; --- Restore registers from stack ---
;pop rdx
;pop rcx
vbroadcastss ymm14, _256f    ; or whatever you named it
vdivps ymm14, ymm14, ymm13      ; ymm14 = 256f / speclen

vmovaps ymm15,ymm1

; ===============
; THE ROW LOOP!!!
; ===============

mov rax,0 ; the tracker for main loop, rbx is the subloop
rowl: ; the jumper marker
; 4k is always hardcoded and 3840/8=480 so must loop 480 times

vpxor ymm7, ymm7, ymm7
cvtsi2ss    xmm7, rax        ; move lower 32-bit of rax into xmm0
vbroadcastss ymm7, xmm7  ; broadcast into all 8 lanes of ymm7 (anyways ymm7 is only used after here)
vmovaps ymm1,ymm15
vfmadd231ps ymm1, ymm4, ymm7

; prepare for main iteration loop
mov rbx,0
vmovups ymm5,ymm1 ; current re
vmovups ymm6,ymm2 ; current im
vpxor ymm7, ymm7, ymm7 ; result vector



; =====================
; THE ITERATION LOOP!!!
; =====================
itrl:

; calculate (ignores nan/inf because anyways nan and inf<=4 all false so will not add on)
vmulps ymm8,ymm5,ymm5 ; re square
vmulps ymm9,ymm6,ymm6 ; im square
vaddps ymm10,ymm5,ymm5 ; double for 2ab
vfmadd132ps ymm6,ymm2,ymm10 ; 2ab+ob
vsubps ymm5,ymm8,ymm9 ; re^2-im^2
vaddps ymm5,ymm5,ymm1 ; re^2-im^2+ore
vaddps ymm10,ymm8,ymm9 ; re^2+im^2 (magnitude and in nonfinite case bc squaring
                       ; eliminates possibility of -inf nan or inf when non finite)
vcmpps ymm11,ymm10,ymm0,2
vpsrld ymm12,ymm11,31
vpaddd ymm7,ymm7,ymm12
vtestps ymm11,ymm11
jz bailout
inc rbx
cmp rbx,rcx
jb itrl



; =====================
; ITERATION LOOP END!!!
; =====================
bailout:
; ymm7 = int32 iteration counts

vcvtdq2ps ymm7, ymm7        ; int -> float
vmulps    ymm7, ymm7, ymm14 ; scale by (256 / speclen)
vcvtps2dq ymm7, ymm7        ; float -> int (rounded)

; --- Save registers on stack ---
;push rcx
;push rdx

; --- Call printf (stack already aligned with sub rsp,8 done earlier) ---
;lea rcx, msg2       ; RCX = pointer to string
;xor rdx, rdx       ; no additional args
;call printf

; --- Restore registers from stack ---
;pop rdx
;pop rcx

; turn to color (HSV then let opencv do the rest)
;vpslld ymm6,ymm7,8 ; destroying the iteration registers doesnt matter anymore
;vmovups ymm6,ymm7 --- nevermind, the stuff is auto-truncated because its basically count*256/spectruml and discarding past top means mod basically
;vmovdqu ymm0, ymmword ptr [mask2]  ; YMM0 = 0xFF repeated

;vpand ymm0, ymm6, ymm0                   ; keep only lowest 8 bits from YMM6

; Narrow 32-bit -> 16-bit
;vpackusdw xmm0, xmm0, xmm0             ; lower 128 bits now 16-bit

; Narrow 16-bit -> 8-bit
;vpackuswb xmm0, xmm0, xmm0             ; lower 64 bits now 8-bit

; Move packed 64-bit value into R15
;vmovq r15, xmm0


; new approach

vmovups ymm6,ymm7
vpshufb xmm6,xmm6,XMMWORD PTR lowbyte_mask
vmovd dword ptr [R8 + rax*8],xmm6
; other 128 bit
vextracti128 xmm6, ymm7, 1
vpshufb xmm6,xmm6,XMMWORD PTR lowbyte_mask
vmovd dword ptr [R8 + rax*8 + 4],xmm6

; Store to memory using RAX as loop index
;mov qword ptr [R8 + rax*8], r15


; lets see if i even wrote anything
; mov qword ptr [R8 + rax*8], 80808080h

; new



vmovaps ymm10,ymm11
vpshufb xmm11,xmm11,XMMWORD PTR lowbyte_mask
vmovd R10, xmm11
not R10
mov dword ptr [R9 + rax*8], r10d
;vmovd [R9 + rax*8],xmm11
; other 128 bit
vextracti128 xmm11, ymm10, 1
vpshufb xmm11,xmm11,XMMWORD PTR lowbyte_mask
vmovd R10, xmm11
not R10
mov dword ptr [R9 + rax*8 + 4], R10d
;vmovd [R9 + rax*8 + 4],xmm6


; Step 1: AND with mask to keep only lower 8 bits per 32-bit lane
;vmovdqu ymm0, ymmword ptr [mask2]  ; mask2 = 0xFF repeated
;vpand ymm7, ymm7, ymm0             ; ymm7 &= mask

; Step 2: Narrow 32-bit -> 16-bit for all 8 lanes (AVX2)
;vpackusdw ymm0, ymm7, ymm7         ; 32->16

; Step 3: Narrow 16-bit -> 8-bit for all 16 lanes (AVX2)
;vpackuswb ymm0, ymm0, ymm0         ; 16->8

; Step 4: Move lower 64 bits to R15
;vmovq r10, xmm0                    ; lower 8 bytes only

; -STAAART-!!!!!
; --- Save registers on stack ---
push rcx
push rdx

; --- Call printf (stack already aligned with sub rsp,8 done earlier) ---
;lea rcx, msg3       ; RCX = pointer to string
;xor rdx, rdx       ; no additional args
;call printf

; --- Restore registers from stack ---
pop rdx
pop rcx
; -ENDDDDDDD-!!!!!
; Step 5: Store to memory
;mov qword ptr [R9 + rax*8], r10





vaddps ymm1,ymm1,ymm4
; ===============
; ROW LOOP END!!!
; ===============
inc RAX
cmp rax,480
jb rowl

; nonvolitile restoration (ABI :((((( ) (I should have read the ABI carefully before coding)
vmovaps xmm6, [rsp + 0*16]
vmovaps xmm7, [rsp + 1*16]
vmovaps xmm8, [rsp + 2*16]
vmovaps xmm9, [rsp + 3*16]
vmovaps xmm10, [rsp + 4*16]
vmovaps xmm11, [rsp + 5*16]
vmovaps xmm12, [rsp + 6*16]

add rsp, 7*16         ; free stack


pop rbx

ret

MakeRowFloat ENDP

MakeRowDouble PROC ; double fp version using AVX256
; first parameter is re xmm0, secons is im xmm1, third is step length xmm2, fourth is max iteration, 5th is spectrum length (last 2 ints), 6th is pointer to H, 7th is pointer to V (s always 1)


; patching a stupid mistake when reading the x64 ABI (aka interweave because why change the code the loop uses everything)
mov rcx,r9
mov edx,dword ptr [rsp+40]
mov r8,qword ptr [rsp+48]
mov r9,qword ptr [rsp+56]
;sub rsp, 8
push rbx

; nonvolitile preservation :( ABI stuff
sub rsp, 7*16         ; reserve 112 bytes for XMM6–XMM12

vmovaps [rsp + 0*16], xmm6
vmovaps [rsp + 1*16], xmm7
vmovaps [rsp + 2*16], xmm8
vmovaps [rsp + 3*16], xmm9
vmovaps [rsp + 4*16], xmm10
vmovaps [rsp + 5*16], xmm11
vmovaps [rsp + 6*16], xmm12


; preperation


vbroadcastsd ymm3,xmm2 ; to change incrments
vbroadcastsd ymm2,xmm1 ; the im is row, doesnt change
vbroadcastsd ymm1,xmm0 ; this is re
; adding increments
vmovupd ymm0,consecutive2
vmulpd ymm0,ymm0,ymm3
vaddpd ymm1,ymm1,ymm0 ; add consecutive increments
; increment for the column each set
movsd xmm4,fourd ; stride length change
vbroadcastsd ymm4,xmm4 ; ymm4 is now dedicated to incrementing ymm1
vmulpd ymm4,ymm4,ymm3


; single-ify
cvtsi2ss xmm0, rdx
vbroadcastss ymm13, xmm0 

cvtsi2sd xmm0, rcx
vbroadcastsd ymm14, xmm0 


vbroadcastsd ymm0,fourd
; --- Save registers on stack ---
;push rcx
;push rdx

; --- Call printf (stack already aligned with sub rsp,8 done earlier) ---
;lea rcx, msg       ; RCX = pointer to string
;xor rdx, rdx       ; no additional args
;call printf

; --- Restore registers from stack ---
;pop rdx
;pop rcx

; single-ify
vbroadcastss ymm14, _256f
vdivps ymm14, ymm14, ymm13      ; 256d / speclen



vmovaps ymm15,ymm1
; ===============
; THE ROW LOOP!!!
; ===============

mov rax,0 ; the tracker for main loop, rbx is the subloop
rowl: ; the jumper marker
; 4k is always hardcoded and 3840/8=480 so must loop 480 times

cvtsi2sd    xmm7, rax        ; move lower 32-bit of rax into xmm0
vbroadcastsd ymm7, xmm7  ; broadcast into all 8 lanes of ymm7 (anyways ymm7 is only used after here)
vmovapd ymm1,ymm15
vfmadd231pd ymm1, ymm4, ymm7

; prepare for main iteration loop
mov rbx,0
vmovupd ymm5,ymm1 ; current re
vmovupd ymm6,ymm2 ; current im
vpxor ymm7, ymm7, ymm7 ; result vector


; =====================
; THE ITERATION LOOP!!!
; =====================
itrl:

; calculate (ignores nan/inf because anyways nan and inf<=4 all false so will not add on)
vmulpd ymm8,ymm5,ymm5 ; re square
vmulpd ymm9,ymm6,ymm6 ; im square
vaddpd ymm10,ymm5,ymm5 ; double for 2ab
vfmadd132pd ymm6,ymm2,ymm10 ; 2ab+ob
vsubpd ymm5,ymm8,ymm9 ; re^2-im^2
vaddpd ymm5,ymm5,ymm1 ; re^2-im^2+ore
vaddpd ymm10,ymm8,ymm9 ; re^2+im^2 (magnitude and in nonfinite case bc squaring
                       ; eliminates possibility of -inf nan or inf when non finite)
vcmppd ymm11,ymm10,ymm0,2
vpsrlq ymm12,ymm11,63 ; change to match
vpaddq ymm7,ymm7,ymm12
vtestpd ymm11,ymm11
jz bailout
inc rbx
cmp rbx,rcx
jb itrl



; =====================
; ITERATION LOOP END!!!
; =====================
bailout:
;vpshufd ymm7, ymm7, 216;0b11011000

; --- Save registers on stack ---
;push rcx
;push rdx

; --- Call printf (stack already aligned with sub rsp,8 done earlier) ---
;lea rcx, msg2       ; RCX = pointer to string
;xor rdx, rdx       ; no additional args
;call printf

; --- Restore registers from stack ---
;pop rdx
;pop rcx

; turn to color (HSV then let opencv do the rest)
;vpslld ymm6,ymm7,8 ; destroying the iteration registers doesnt matter anymore
;vmovups ymm6,ymm7 --- nevermind, the stuff is auto-truncated because its basically count*256/spectruml and discarding past top means mod basically
;vmovdqu ymm0, ymmword ptr [mask2]  ; YMM0 = 0xFF repeated

;vpand ymm0, ymm6, ymm0                   ; keep only lowest 8 bits from YMM6

; Narrow 32-bit -> 16-bit
;vpackusdw xmm0, xmm0, xmm0             ; lower 128 bits now 16-bit

; Narrow 16-bit -> 8-bit
;vpackuswb xmm0, xmm0, xmm0             ; lower 64 bits now 8-bit

; Move packed 64-bit value into R15
;vmovq r15, xmm0


; the scaler
;vcvtsi2sd 
; you know what why am i using 64 bit when it fits in 32 bit and i can just use it as 32 bit because
;the small 64 bit is a 32 bit but with extra zeros :)
vcvtdq2ps ymm7, ymm7        ; int -> float
vmulps    ymm7, ymm7, ymm14 ; scale by (256 / speclen)
vcvtps2dq ymm7, ymm7        ; float -> int (rounded)
; new approach
; must update memory stuff (mainly using diferent interval)

; ymm7 = int64 iteration counts

;vcvtqq2pd ymm7, ymm7        ; int64 -> double
;vmulpd     ymm7, ymm7, ymm14
;vcvtpd2qq ymm7, ymm7        ; double -> int64


vmovupd ymm6,ymm7


vpshufb xmm6,xmm6,XMMWORD PTR lowbyte_mask_d
vmovd dword ptr [R8 + rax*4],xmm6 ; allocated extra space for the junk

; other 128 bit
vextracti128 xmm6, ymm7, 1
vpshufb xmm6,xmm6,XMMWORD PTR lowbyte_mask_d
vmovd dword ptr [R8 + rax*4 + 2],xmm6

; Store to memory using RAX as loop index
;mov qword ptr [R8 + rax*8], r15


; lets see if i even wrote anything
; mov qword ptr [R8 + rax*8], 80808080h

; new

vmovapd ymm10,ymm11
vpshufb xmm11,xmm11,XMMWORD PTR lowbyte_mask_d
vmovd R10, xmm11
not R10
mov word ptr [R9 + rax*4], r10w
;vmovd [R9 + rax*8],xmm11
; other 128 bit
vextracti128 xmm11, ymm10, 1
vpshufb xmm11,xmm11,XMMWORD PTR lowbyte_mask_d
vmovd R10, xmm11
not R10
mov word ptr [R9 + rax*4 + 2], R10w
;vmovd [R9 + rax*8 + 4],xmm6


; Step 1: AND with mask to keep only lower 8 bits per 32-bit lane
;vmovdqu ymm0, ymmword ptr [mask2]  ; mask2 = 0xFF repeated
;vpand ymm7, ymm7, ymm0             ; ymm7 &= mask

; Step 2: Narrow 32-bit -> 16-bit for all 8 lanes (AVX2)
;vpackusdw ymm0, ymm7, ymm7         ; 32->16

; Step 3: Narrow 16-bit -> 8-bit for all 16 lanes (AVX2)
;vpackuswb ymm0, ymm0, ymm0         ; 16->8

; Step 4: Move lower 64 bits to R15
;vmovq r10, xmm0                    ; lower 8 bytes only

; -STAAART-!!!!!
; --- Save registers on stack ---
push rcx
push rdx

; --- Call printf (stack already aligned with sub rsp,8 done earlier) ---
;lea rcx, msg3       ; RCX = pointer to string
;xor rdx, rdx       ; no additional args
;call printf

; --- Restore registers from stack ---
pop rdx
pop rcx
; -ENDDDDDDD-!!!!!
; Step 5: Store to memory
;mov qword ptr [R9 + rax*8], r10





vaddpd ymm1,ymm1,ymm4
; ===============
; ROW LOOP END!!!
; ===============
inc RAX
cmp rax,960 ; change to 960 rathe than 480 because stride length half
jb rowl

; nonvolitile restoration (ABI :((((( ) (I should have read the ABI carefully before coding)
vmovaps xmm6, [rsp + 0*16]
vmovaps xmm7, [rsp + 1*16]
vmovaps xmm8, [rsp + 2*16]
vmovaps xmm9, [rsp + 3*16]
vmovaps xmm10, [rsp + 4*16]
vmovaps xmm11, [rsp + 5*16]
vmovaps xmm12, [rsp + 6*16]

add rsp, 7*16         ; free stack


pop rbx

ret

MakeRowDouble ENDP

END