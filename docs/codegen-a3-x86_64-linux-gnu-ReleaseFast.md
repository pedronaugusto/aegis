# x86_64-linux-gnu ReleaseFast parity

Zig 0.17.0, LLVM, baseline CPU, stripped object. All owner and A3 scalar pairs have identical emitted instructions (shared aliases or normalized assembly); storage/alignment assertions compile.

## secret_s32

Symbols → `parity.baselineSecretS32` / `parity.baselineSecretS32`; baseline/wrapper machine code 34/34 bytes.

```asm
 push rbp
 mov rbp rsp
 mov qword ptr [rbp - 16] rdi
 lea rax [rbp - 16]
 mov qword ptr [rbp - 8] rax
 movzx eax byte ptr [rdi + 31]
 xor al byte ptr [rdi]
 xorps xmm0 xmm0
 movups xmmword ptr [rdi + 16] xmm0
 movups xmmword ptr [rdi] xmm0
 pop rbp
 ret
```

```llvm
define private zeroext i8 @parity.baselineSecretS32(ptr nonnull align 1 %0) unnamed_addr #7 {
  %2 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %2) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i = load i8, ptr %0, align 1
  %3 = getelementptr i8, ptr %0, i64 31
  %.val1.i = load i8, ptr %3, align 1
  %4 = xor i8 %.val1.i, %.val.i
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %0, i8 0, i64 32, i1 true)
  ret i8 %4
}

```

## transfer_s32

Symbols → `parity.baselineTransferS32` / `parity.baselineTransferS32`; baseline/wrapper machine code 100/100 bytes.

```asm
 push rbp
 mov rbp rsp
 sub rsp 32
 mov qword ptr [rbp - 8] rdi
 lea rax [rbp - 8]
 mov qword ptr [rbp - 24] rax
 lea rcx [rdi + 32]
 lea rdx [rsi + 32]
 cmp rsi rcx
 setae cl
 cmp rdi rdx
 setae dl
 or dl cl
 je label1
 movups xmm0 xmmword ptr [rdi]
 movups xmm1 xmmword ptr [rdi + 16]
 movups xmmword ptr [rsi + 16] xmm1
 movups xmmword ptr [rsi] xmm0
 xorps xmm0 xmm0
 movups xmmword ptr [rdi] xmm0
 movups xmmword ptr [rdi + 16] xmm0
 mov qword ptr [rbp - 8] rsi
 mov qword ptr [rbp - 16] rax
 movzx eax byte ptr [rsi + 31]
 xor al byte ptr [rsi]
 movups xmmword ptr [rsi + 16] xmm0
 movups xmmword ptr [rsi] xmm0
 add rsp 32
 pop rbp
 ret
 call ".Ldebug.FullPanic((function 'defaultPanic')).memcpyAlias"
```

```llvm
define private zeroext i8 @parity.baselineTransferS32(ptr nonnull align 1 %0, ptr nonnull align 1 %1) unnamed_addr #7 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 32
  %7 = icmp uge ptr %1, %5
  %8 = icmp uge ptr %0, %6
  %9 = or i1 %7, %8
  br i1 %9, label %cases.transfer__func_345.exit, label %10

10:                                               ; preds = %2
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable

cases.transfer__func_345.exit:                    ; preds = %2
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %1, ptr noundef nonnull align 1 dereferenceable(32) %0, i64 32, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %0, i8 0, i64 32, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %1, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %.val.i = load i8, ptr %1, align 1
  %11 = getelementptr i8, ptr %1, i64 31
  %.val1.i = load i8, ptr %11, align 1
  %12 = xor i8 %.val1.i, %.val.i
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %1, i8 0, i64 32, i1 true)
  ret i8 %12
}

```

## secret_s48

Symbols → `parity.baselineSecretS48` / `parity.baselineSecretS48`; baseline/wrapper machine code 38/38 bytes.

```asm
 push rbp
 mov rbp rsp
 mov qword ptr [rbp - 16] rdi
 lea rax [rbp - 16]
 mov qword ptr [rbp - 8] rax
 movzx eax byte ptr [rdi + 47]
 xor al byte ptr [rdi]
 xorps xmm0 xmm0
 movups xmmword ptr [rdi + 16] xmm0
 movups xmmword ptr [rdi + 32] xmm0
 movups xmmword ptr [rdi] xmm0
 pop rbp
 ret
```

```llvm
define private zeroext i8 @parity.baselineSecretS48(ptr nonnull align 1 %0) unnamed_addr #7 {
  %2 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %2) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i = load i8, ptr %0, align 1
  %3 = getelementptr i8, ptr %0, i64 47
  %.val1.i = load i8, ptr %3, align 1
  %4 = xor i8 %.val1.i, %.val.i
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %0, i8 0, i64 48, i1 true)
  ret i8 %4
}

```

## transfer_s48

Symbols → `parity.baselineTransferS48` / `parity.baselineTransferS48`; baseline/wrapper machine code 116/116 bytes.

```asm
 push rbp
 mov rbp rsp
 sub rsp 32
 mov qword ptr [rbp - 8] rdi
 lea rax [rbp - 8]
 mov qword ptr [rbp - 24] rax
 lea rcx [rdi + 48]
 lea rdx [rsi + 48]
 cmp rsi rcx
 setae cl
 cmp rdi rdx
 setae dl
 or dl cl
 je label1
 movups xmm0 xmmword ptr [rdi]
 movups xmm1 xmmword ptr [rdi + 16]
 movups xmm2 xmmword ptr [rdi + 32]
 movups xmmword ptr [rsi + 32] xmm2
 movups xmmword ptr [rsi + 16] xmm1
 movups xmmword ptr [rsi] xmm0
 xorps xmm0 xmm0
 movups xmmword ptr [rdi] xmm0
 movups xmmword ptr [rdi + 16] xmm0
 movups xmmword ptr [rdi + 32] xmm0
 mov qword ptr [rbp - 8] rsi
 mov qword ptr [rbp - 16] rax
 movzx eax byte ptr [rsi + 47]
 xor al byte ptr [rsi]
 movups xmmword ptr [rsi + 16] xmm0
 movups xmmword ptr [rsi + 32] xmm0
 movups xmmword ptr [rsi] xmm0
 add rsp 32
 pop rbp
 ret
 call ".Ldebug.FullPanic((function 'defaultPanic')).memcpyAlias"
```

```llvm
define private zeroext i8 @parity.baselineTransferS48(ptr nonnull align 1 %0, ptr nonnull align 1 %1) unnamed_addr #7 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 48
  %7 = icmp uge ptr %1, %5
  %8 = icmp uge ptr %0, %6
  %9 = or i1 %7, %8
  br i1 %9, label %cases.transfer__func_338.exit, label %10

10:                                               ; preds = %2
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable

cases.transfer__func_338.exit:                    ; preds = %2
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %1, ptr noundef nonnull align 1 dereferenceable(48) %0, i64 48, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %0, i8 0, i64 48, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %1, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %.val.i = load i8, ptr %1, align 1
  %11 = getelementptr i8, ptr %1, i64 47
  %.val1.i = load i8, ptr %11, align 1
  %12 = xor i8 %.val1.i, %.val.i
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %1, i8 0, i64 48, i1 true)
  ret i8 %12
}

```

## secret_material

Symbols → `parity.baselineSecretMaterial` / `parity.baselineSecretMaterial`; baseline/wrapper machine code 52/52 bytes.

```asm
 push rbp
 mov rbp rsp
 push rbx
 sub rsp 24
 mov qword ptr [rbp - 24] rdi
 lea rax [rbp - 24]
 mov qword ptr [rbp - 16] rax
 movzx ebx byte ptr [rdi + 536]
 xor bl byte ptr [rdi + 16]
 mov edx 1056
 xor esi esi
 call memset@PLT
 mov eax ebx
 add rsp 24
 pop rbx
 pop rbp
 ret
```

```llvm
define private zeroext i8 @parity.baselineSecretMaterial(ptr nonnull align 8 %0) unnamed_addr #7 {
  %2 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %2) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %3 = getelementptr i8, ptr %0, i64 16
  %.val.i = load i8, ptr %3, align 8
  %4 = getelementptr i8, ptr %0, i64 536
  %.val1.i = load i8, ptr %4, align 8
  %5 = xor i8 %.val1.i, %.val.i
  call void @llvm.memset.p0.i64(ptr nonnull align 8 %0, i8 0, i64 1056, i1 true)
  ret i8 %5
}

```

## transfer_material

Symbols → `parity.baselineTransferMaterial` / `parity.baselineTransferMaterial`; baseline/wrapper machine code 146/146 bytes.

```asm
 push rbp
 mov rbp rsp
 push r15
 push r14
 push rbx
 sub rsp 24
 mov qword ptr [rbp - 32] rdi
 lea r15 [rbp - 32]
 mov qword ptr [rbp - 48] r15
 lea rax [rdi + 1056]
 lea rcx [rsi + 1056]
 cmp rsi rax
 setae al
 cmp rdi rcx
 setae cl
 or cl al
 je label1
 mov rbx rsi
 mov r14 rdi
 mov edx 1056
 mov rdi rsi
 mov rsi r14
 call memcpy@PLT
 mov edx 1056
 mov rdi r14
 xor esi esi
 call memset@PLT
 mov qword ptr [rbp - 32] rbx
 mov qword ptr [rbp - 40] r15
 movzx r14d byte ptr [rbx + 536]
 xor r14b byte ptr [rbx + 16]
 mov edx 1056
 mov rdi rbx
 xor esi esi
 call memset@PLT
 mov eax r14d
 add rsp 24
 pop rbx
 pop r14
 pop r15
 pop rbp
 ret
 call ".Ldebug.FullPanic((function 'defaultPanic')).memcpyAlias"
```

```llvm
define private zeroext i8 @parity.baselineTransferMaterial(ptr nonnull align 8 %0, ptr nonnull align 8 %1) unnamed_addr #7 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 1056
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 1056
  %7 = icmp uge ptr %1, %5
  %8 = icmp uge ptr %0, %6
  %9 = or i1 %7, %8
  br i1 %9, label %cases.transfer__func_332.exit, label %10

10:                                               ; preds = %2
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable

cases.transfer__func_332.exit:                    ; preds = %2
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(1056) %1, ptr noundef nonnull align 8 dereferenceable(1056) %0, i64 1056, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 8 %0, i8 0, i64 1056, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %1, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %11 = getelementptr i8, ptr %1, i64 16
  %.val.i = load i8, ptr %11, align 8
  %12 = getelementptr i8, ptr %1, i64 536
  %.val1.i = load i8, ptr %12, align 8
  %13 = xor i8 %.val1.i, %.val.i
  call void @llvm.memset.p0.i64(ptr nonnull align 8 %1, i8 0, i64 1056, i1 true)
  ret i8 %13
}

```

## cleanup

Symbols → `parity.baselineCleanup` / `parity.baselineCleanup`; baseline/wrapper machine code 58/58 bytes.

```asm
 push rbp
 mov rbp rsp
 mov byte ptr [rbp - 1] 0
 xorps xmm0 xmm0
 movaps xmmword ptr [rbp - 32] xmm0
 movaps xmmword ptr [rbp - 48] xmm0
 mov byte ptr [rbp - 2] 0
 mov word ptr [rbp - 4] 0
 mov dword ptr [rbp - 8] 0
 mov qword ptr [rbp - 16] 0
 test dil 1
 mov eax 1
 cmove eax esi
 pop rbp
 ret
```

```llvm
define private zeroext i8 @parity.baselineCleanup(i8 %0, i8 zeroext %1) unnamed_addr #24 {
  %.sroa.0.i = alloca i8, align 1
  %.sroa.4.i = alloca [47 x i8], align 1
  %3 = trunc nuw i8 %0 to i1
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.0.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.4.i)
  store volatile i8 0, ptr %.sroa.0.i, align 1
  call void @llvm.memset.p0.i64(ptr align 1 %.sroa.4.i, i8 0, i64 47, i1 true)
  %..i = select i1 %3, i8 1, i8 %1
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.0.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.4.i)
  ret i8 %..i
}

```

## cleanup_material

Symbols → `parity.baselineCleanupMaterial` / `parity.baselineCleanupMaterial`; baseline/wrapper machine code 130/130 bytes.

```asm
 push rbp
 mov rbp rsp
 push r14
 push rbx
 sub rsp 1072
 mov ebx esi
 mov r14d edi
 mov qword ptr [rbp - 56] 0
 mov qword ptr [rbp - 48] 0
 lea rdi [rbp - 1080]
 mov edx 512
 xor esi esi
 call memset@PLT
 mov qword ptr [rbp - 40] 0
 mov byte ptr [rbp - 24] 0
 lea rdi [rbp - 567]
 mov edx 511
 xor esi esi
 call memset@PLT
 mov byte ptr [rbp - 25] 0
 mov dword ptr [rbp - 32] 0
 mov word ptr [rbp - 28] 0
 mov byte ptr [rbp - 26] 0
 test r14b 1
 mov eax 1
 cmove eax ebx
 add rsp 1072
 pop rbx
 pop r14
 pop rbp
 ret
```

```llvm
define private zeroext i8 @parity.baselineCleanupMaterial(i8 %0, i8 zeroext %1) unnamed_addr #24 {
  %.sroa.0.sroa.0.i = alloca i64, align 8
  %.sroa.0.sroa.3.i = alloca i64, align 8
  %.sroa.0.sroa.4.i = alloca [512 x i8], align 8
  %.sroa.0.sroa.5.i = alloca i64, align 8
  %.sroa.31.i = alloca i8, align 8
  %.sroa.4.sroa.0.i = alloca [511 x i8], align 1
  %.sroa.4.sroa.3.i = alloca i8, align 1
  %.sroa.4.sroa.4.i = alloca [7 x i8], align 1
  %3 = trunc nuw i8 %0 to i1
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.0.sroa.0.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.0.sroa.3.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.0.sroa.4.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.0.sroa.5.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.31.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.4.sroa.0.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.4.sroa.3.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.4.sroa.4.i)
  store volatile i64 0, ptr %.sroa.0.sroa.0.i, align 8
  store volatile i64 0, ptr %.sroa.0.sroa.3.i, align 8
  call void @llvm.memset.p0.i64(ptr align 8 %.sroa.0.sroa.4.i, i8 0, i64 512, i1 true)
  store volatile i64 0, ptr %.sroa.0.sroa.5.i, align 8
  store volatile i8 0, ptr %.sroa.31.i, align 8
  call void @llvm.memset.p0.i64(ptr align 1 %.sroa.4.sroa.0.i, i8 0, i64 511, i1 true)
  store volatile i8 0, ptr %.sroa.4.sroa.3.i, align 1
  call void @llvm.memset.p0.i64(ptr align 1 %.sroa.4.sroa.4.i, i8 0, i64 7, i1 true)
  %..i = select i1 %3, i8 1, i8 %1
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.0.sroa.0.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.0.sroa.3.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.0.sroa.4.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.0.sroa.5.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.31.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.4.sroa.0.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.4.sroa.3.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.4.sroa.4.i)
  ret i8 %..i
}

```

## budget

Symbols → `parity.baselineBudget` / `parity.baselineBudget`; baseline/wrapper machine code 228/228 bytes.

```asm
 push rbp
 mov rbp rsp
 sub rsp 32
 mov cl 1
 xor eax eax
 lock cmpxchg byte ptr [rdi + 16] cl
 je label2
 pause
 xor eax eax
 lock cmpxchg byte ptr [rdi + 16] cl
 jne label1
 mov qword ptr [rbp - 8] rdi
 lea rcx [rbp - 8]
 mov qword ptr [rbp - 32] rcx
 mov rax qword ptr [rdi]
 cmp rax 63
 ja label3
 mov rdx qword ptr [rdi + 8]
 mov r8d 16777216
 sub r8 rdx
 setb r9b
 cmp rsi r8
 seta r8b
 or r8b r9b
 je label4
 xor eax eax
 mov byte ptr [rdi + 16] 0
 add rsp 32
 pop rbp
 ret
 add rax 1
 mov qword ptr [rdi] rax
 add rdx rsi
 mov qword ptr [rdi + 8] rdx
 mov qword ptr [rbp - 8] rdi
 mov qword ptr [rbp - 24] rcx
 mov byte ptr [rdi + 16] 0
 mov dl 1
 xor eax eax
 lock cmpxchg byte ptr [rdi + 16] dl
 je label6
 pause
 xor eax eax
 lock cmpxchg byte ptr [rdi + 16] dl
 jne label5
 mov rax qword ptr [rdi + 8]
 cmp rax rsi
 jb label7
 mov rdx qword ptr [rdi]
 test rdx rdx
 je label7
 add rdx -1
 mov qword ptr [rdi] rdx
 sub rax rsi
 jb label8
 mov qword ptr [rdi + 8] rax
 mov qword ptr [rbp - 8] rdi
 mov qword ptr [rbp - 16] rcx
 mov al 1
 mov byte ptr [rdi + 16] 0
 add rsp 32
 pop rbp
 ret
 mov edi offset .L__anon_16732
 mov esi 36
 call .Ldebug.defaultPanic
 call ".Ldebug.FullPanic((function 'defaultPanic')).integerOverflow"
```

```llvm
define private zeroext range(i8 0, 2) i8 @parity.baselineBudget(ptr nonnull align 8 %0, i64 %1) unnamed_addr #7 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %7 = cmpxchg weak ptr %6, i8 0, i8 1 acquire monotonic, align 1
  %8 = extractvalue { i8, i1 } %7, 1
  br i1 %8, label %cases.lock__func_327.exit.i, label %.lr.ph.i.i.preheader

.lr.ph.i.i.preheader:                             ; preds = %2
  br label %.lr.ph.i.i

.lr.ph.i.i:                                       ; preds = %.lr.ph.i.i.preheader, %.lr.ph.i.i
  tail call void asm sideeffect "pause", "~{dirflag},~{fpsr},~{flags}"() #29
  %sunkaddr = getelementptr inbounds i8, ptr %0, i64 16
  %9 = cmpxchg weak ptr %sunkaddr, i8 0, i8 1 acquire monotonic, align 1
  %10 = extractvalue { i8, i1 } %9, 1
  br i1 %10, label %cases.lock__func_327.exit.i, label %.lr.ph.i.i

cases.lock__func_327.exit.i:                      ; preds = %.lr.ph.i.i, %2
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %11 = load i64, ptr %0, align 8
  %12 = icmp ugt i64 %11, 63
  br i1 %12, label %cases.budget__func_326.exit, label %13

13:                                               ; preds = %cases.lock__func_327.exit.i
  %14 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %15 = load i64, ptr %14, align 8
  %16 = call { i64, i1 } @llvm.usub.with.overflow.i64(i64 16777216, i64 %15)
  %math = extractvalue { i64, i1 } %16, 0
  %ov = extractvalue { i64, i1 } %16, 1
  %17 = icmp ugt i64 %1, %math
  %or.cond.i.i = select i1 %ov, i1 true, i1 %17
  br i1 %or.cond.i.i, label %cases.budget__func_326.exit, label %18

18:                                               ; preds = %13
  %19 = add nuw nsw i64 %11, 1
  store i64 %19, ptr %0, align 8
  %20 = add nuw nsw i64 %15, %1
  %sunkaddr5 = getelementptr inbounds i8, ptr %0, i64 8
  store i64 %20, ptr %sunkaddr5, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %sunkaddr6 = getelementptr inbounds i8, ptr %0, i64 16
  store atomic i8 0, ptr %sunkaddr6 release, align 8
  %21 = cmpxchg weak ptr %sunkaddr6, i8 0, i8 1 acquire monotonic, align 1
  %22 = extractvalue { i8, i1 } %21, 1
  br i1 %22, label %cases.lock__func_327.exit9.i, label %.lr.ph.i8.i.preheader

.lr.ph.i8.i.preheader:                            ; preds = %18
  br label %.lr.ph.i8.i

.lr.ph.i8.i:                                      ; preds = %.lr.ph.i8.i.preheader, %.lr.ph.i8.i
  call void asm sideeffect "pause", "~{dirflag},~{fpsr},~{flags}"() #29
  %sunkaddr7 = getelementptr inbounds i8, ptr %0, i64 16
  %23 = cmpxchg weak ptr %sunkaddr7, i8 0, i8 1 acquire monotonic, align 1
  %24 = extractvalue { i8, i1 } %23, 1
  br i1 %24, label %cases.lock__func_327.exit9.i, label %.lr.ph.i8.i

cases.lock__func_327.exit9.i:                     ; preds = %.lr.ph.i8.i, %18
  %sunkaddr8 = getelementptr inbounds i8, ptr %0, i64 8
  %25 = load i64, ptr %sunkaddr8, align 8
  %26 = icmp ult i64 %25, %1
  br i1 %26, label %.critedge.i.i, label %27

27:                                               ; preds = %cases.lock__func_327.exit9.i
  %28 = load i64, ptr %0, align 8
  %29 = icmp eq i64 %28, 0
  br i1 %29, label %.critedge.i.i, label %30

.critedge.i.i:                                    ; preds = %27, %cases.lock__func_327.exit9.i
  call fastcc void @debug.defaultPanic(ptr nonnull readonly align 1 @__anon_16732, i64 36)
  unreachable

30:                                               ; preds = %27
  %31 = add i64 %28, -1
  store i64 %31, ptr %0, align 8
  %32 = call { i64, i1 } @llvm.usub.with.overflow.i64(i64 %25, i64 %1)
  %33 = extractvalue { i64, i1 } %32, 1
  br i1 %33, label %34, label %cases.uncharge.exit.i

34:                                               ; preds = %30
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).integerOverflow"()
  unreachable

cases.uncharge.exit.i:                            ; preds = %30
  %35 = extractvalue { i64, i1 } %32, 0
  %sunkaddr9 = getelementptr inbounds i8, ptr %0, i64 8
  store i64 %35, ptr %sunkaddr9, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  br label %cases.budget__func_326.exit

cases.budget__func_326.exit:                      ; preds = %cases.lock__func_327.exit.i, %13, %cases.uncharge.exit.i
  %common.ret.op.i11.i = phi i8 [ 1, %cases.uncharge.exit.i ], [ 0, %13 ], [ 0, %cases.lock__func_327.exit.i ]
  %sunkaddr10 = getelementptr inbounds i8, ptr %0, i64 16
  store atomic i8 0, ptr %sunkaddr10 release, align 8
  ret i8 %common.ret.op.i11.i
}

```

## job

Symbols → `parity.baselineJob` / `parity.baselineJob`; baseline/wrapper machine code 149/149 bytes.

```asm
 push rbp
 mov rbp rsp
 sub rsp 32
 mov dl 1
 xor eax eax
 lock cmpxchg byte ptr [rdi + 24] dl
 je label2
 pause
 xor eax eax
 lock cmpxchg byte ptr [rdi + 24] dl
 jne label1
 mov qword ptr [rdi] rsi
 mov byte ptr [rdi + 8] 1
 mov byte ptr [rdi + 16] 1
 mov qword ptr [rbp - 8] rdi
 lea rcx [rbp - 8]
 mov qword ptr [rbp - 24] rcx
 mov byte ptr [rdi + 24] 0
 xor eax eax
 lock cmpxchg byte ptr [rdi + 24] dl
 je label4
 mov dl 1
 pause
 xor eax eax
 lock cmpxchg byte ptr [rdi + 24] dl
 jne label3
 test byte ptr [rdi + 8] 1
 je label5
 mov rax qword ptr [rdi]
 xorps xmm0 xmm0
 movups xmmword ptr [rdi] xmm0
 mov byte ptr [rdi + 16] 2
 mov qword ptr [rbp - 8] rdi
 mov qword ptr [rbp - 16] rcx
 mov byte ptr [rdi + 24] 0
 add rsp 32
 pop rbp
 ret
 call ".Ldebug.FullPanic((function 'defaultPanic')).unwrapNull"
```

```llvm
define private i64 @parity.baselineJob(ptr nonnull align 8 %0, i64 %1) unnamed_addr #7 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %6 = cmpxchg weak ptr %5, i8 0, i8 1 acquire monotonic, align 1
  %7 = extractvalue { i8, i1 } %6, 1
  br i1 %7, label %cases.lock__func_325.exit.i, label %.lr.ph.i.i.preheader

.lr.ph.i.i.preheader:                             ; preds = %2
  br label %.lr.ph.i.i

.lr.ph.i.i:                                       ; preds = %.lr.ph.i.i.preheader, %.lr.ph.i.i
  tail call void asm sideeffect "pause", "~{dirflag},~{fpsr},~{flags}"() #29
  %sunkaddr = getelementptr inbounds i8, ptr %0, i64 24
  %8 = cmpxchg weak ptr %sunkaddr, i8 0, i8 1 acquire monotonic, align 1
  %9 = extractvalue { i8, i1 } %8, 1
  br i1 %9, label %cases.lock__func_325.exit.i, label %.lr.ph.i.i

cases.lock__func_325.exit.i:                      ; preds = %.lr.ph.i.i, %2
  store i64 %1, ptr %0, align 8
  %.sroa.2.0..0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i8 1, ptr %.sroa.2.0..0..sroa_idx.i, align 8
  %10 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i8 1, ptr %10, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %sunkaddr1 = getelementptr inbounds i8, ptr %0, i64 24
  store atomic i8 0, ptr %sunkaddr1 release, align 8
  %11 = cmpxchg weak ptr %sunkaddr1, i8 0, i8 1 acquire monotonic, align 1
  %12 = extractvalue { i8, i1 } %11, 1
  br i1 %12, label %cases.lock__func_325.exit15.i, label %.lr.ph.i14.i.preheader

.lr.ph.i14.i.preheader:                           ; preds = %cases.lock__func_325.exit.i
  br label %.lr.ph.i14.i

.lr.ph.i14.i:                                     ; preds = %.lr.ph.i14.i.preheader, %.lr.ph.i14.i
  call void asm sideeffect "pause", "~{dirflag},~{fpsr},~{flags}"() #29
  %sunkaddr2 = getelementptr inbounds i8, ptr %0, i64 24
  %13 = cmpxchg weak ptr %sunkaddr2, i8 0, i8 1 acquire monotonic, align 1
  %14 = extractvalue { i8, i1 } %13, 1
  br i1 %14, label %cases.lock__func_325.exit15.i, label %.lr.ph.i14.i

cases.lock__func_325.exit15.i:                    ; preds = %.lr.ph.i14.i, %cases.lock__func_325.exit.i
  %sunkaddr3 = getelementptr inbounds i8, ptr %0, i64 8
  %.sroa.211.0.copyload.i = load i8, ptr %sunkaddr3, align 8
  %15 = trunc nuw i8 %.sroa.211.0.copyload.i to i1
  br i1 %15, label %cases.job__func_324.exit, label %16

16:                                               ; preds = %cases.lock__func_325.exit15.i
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).unwrapNull"()
  unreachable

cases.job__func_324.exit:                         ; preds = %cases.lock__func_325.exit15.i
  %.sroa.010.0.copyload.i = load i64, ptr %0, align 8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, i8 0, i64 16, i1 false)
  %sunkaddr4 = getelementptr inbounds i8, ptr %0, i64 16
  store i8 2, ptr %sunkaddr4, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory},~{dirflag},~{fpsr},~{flags}"(ptr nonnull %3) #29
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %sunkaddr5 = getelementptr inbounds i8, ptr %0, i64 24
  store atomic i8 0, ptr %sunkaddr5 release, align 8
  ret i64 %.sroa.010.0.copyload.i
}

```

## increment

Symbols → `parity.baselineIncrement` / `parity.baselineIncrement`; baseline/wrapper machine code 37/37 bytes.

```asm
 push rbp
 mov rbp rsp
 mov cl 1
 xor eax eax
 lock cmpxchg byte ptr [rdi + 8] cl
 je label2
 pause
 xor eax eax
 lock cmpxchg byte ptr [rdi + 8] cl
 jne label1
 add qword ptr [rdi] 1
 mov byte ptr [rdi + 8] 0
 pop rbp
 ret
```

```llvm
define private void @parity.baselineIncrement(ptr nonnull align 8 captures(none) %0) unnamed_addr #7 {
  %2 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %3 = cmpxchg weak ptr %2, i8 0, i8 1 acquire monotonic, align 1
  %4 = extractvalue { i8, i1 } %3, 1
  br i1 %4, label %cases.increment__func_322.exit, label %.lr.ph.i.i.preheader

.lr.ph.i.i.preheader:                             ; preds = %1
  br label %.lr.ph.i.i

.lr.ph.i.i:                                       ; preds = %.lr.ph.i.i.preheader, %.lr.ph.i.i
  tail call void asm sideeffect "pause", "~{dirflag},~{fpsr},~{flags}"() #29
  %sunkaddr = getelementptr inbounds i8, ptr %0, i64 8
  %5 = cmpxchg weak ptr %sunkaddr, i8 0, i8 1 acquire monotonic, align 1
  %6 = extractvalue { i8, i1 } %5, 1
  br i1 %6, label %cases.increment__func_322.exit, label %.lr.ph.i.i

cases.increment__func_322.exit:                   ; preds = %.lr.ph.i.i, %1
  %7 = load i64, ptr %0, align 8
  %8 = add i64 %7, 1
  store i64 %8, ptr %0, align 8
  %sunkaddr1 = getelementptr inbounds i8, ptr %0, i64 8
  store atomic i8 0, ptr %sunkaddr1 release, align 8
  ret void
}

```

## numeric_add

Symbols → `parity.baselineNumericAdd` / `parity.wrapperNumericAdd`; baseline/wrapper machine code 15/15 bytes.

```asm
 push rbp
 mov rbp rsp
 xor eax eax
 add rdi rsi
 cmovae rax rdi
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericAdd(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %0, i64 %1)
  %4 = extractvalue { i64, i1 } %3, 0
  %5 = extractvalue { i64, i1 } %3, 1
  %6 = select i1 %5, i64 0, i64 %4
  ret i64 %6
}

```

## numeric_sub

Symbols → `parity.baselineNumericSub` / `parity.baselineNumericSub`; baseline/wrapper machine code 15/15 bytes.

```asm
 push rbp
 mov rbp rsp
 xor eax eax
 sub rdi rsi
 cmovae rax rdi
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericSub(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call i64 @llvm.usub.sat.i64(i64 %0, i64 %1)
  ret i64 %3
}

```

## numeric_mul

Symbols → `parity.baselineNumericMul` / `parity.wrapperNumericMul`; baseline/wrapper machine code 18/18 bytes.

```asm
 push rbp
 mov rbp rsp
 mov rax rdi
 xor ecx ecx
 mul rsi
 cmovo rax rcx
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericMul(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call { i64, i1 } @llvm.umul.with.overflow.i64(i64 %0, i64 %1)
  %4 = extractvalue { i64, i1 } %3, 0
  %5 = extractvalue { i64, i1 } %3, 1
  %6 = select i1 %5, i64 0, i64 %4
  ret i64 %6
}

```

## numeric_div

Symbols → `parity.baselineNumericDiv` / `parity.baselineNumericDiv`; baseline/wrapper machine code 67/67 bytes.

```asm
 push rbp
 mov rbp rsp
 test rsi rsi
 je label1
 movabs rax -9223372036854775808
 xor rax rdi
 mov rcx rsi
 not rcx
 or rcx rax
 jne label2
 xor eax eax
 pop rbp
 ret
 mov rax rsi
 or rax rdi
 shr rax 32
 test rax rax
 je label3
 je label3
 mov rax rdi
 cqo
 idiv rsi
 pop rbp
 ret
 mov eax edi
 xor edx edx
 div esi
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericDiv(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = icmp eq i64 %1, 0
  br i1 %3, label %numeric.operation__func_303.exit, label %4

4:                                                ; preds = %2
  %5 = icmp eq i64 %0, -9223372036854775808
  %6 = icmp eq i64 %1, -1
  %7 = and i1 %5, %6
  br i1 %7, label %numeric.operation__func_303.exit, label %8

8:                                                ; preds = %4
  %9 = or i64 %0, %1
  %10 = and i64 %9, -4294967296
  %11 = icmp eq i64 %10, 0
  br i1 %11, label %12, label %17

12:                                               ; preds = %8
  %13 = trunc i64 %1 to i32
  %14 = trunc i64 %0 to i32
  %15 = udiv i32 %14, %13
  %16 = zext i32 %15 to i64
  br label %numeric.operation__func_303.exit

17:                                               ; preds = %8
  %18 = sdiv i64 %0, %1
  br label %numeric.operation__func_303.exit

numeric.operation__func_303.exit:                 ; preds = %12, %17, %2, %4
  %common.ret.op.i = phi i64 [ 0, %4 ], [ 0, %2 ], [ %16, %12 ], [ %18, %17 ]
  ret i64 %common.ret.op.i
}

```

## numeric_rem

Symbols → `parity.baselineNumericRem` / `parity.wrapperNumericRem`; baseline/wrapper machine code 53/53 bytes.

```asm
 push rbp
 mov rbp rsp
 lea rax [rsi - 1]
 cmp rax -3
 ja label1
 mov rax rsi
 or rax rdi
 shr rax 32
 test rax rax
 je label2
 je label2
 mov rax rdi
 cqo
 idiv rsi
 mov rax rdx
 pop rbp
 ret
 xor eax eax
 pop rbp
 ret
 mov eax edi
 xor edx edx
 div esi
 mov eax edx
 pop rbp
 ret
```

```llvm
define private range(i64 -9223372036854775807, -9223372036854775808) i64 @parity.baselineNumericRem(i64 %0, i64 %1) unnamed_addr #4 {
  %.off.i = add i64 %1, -1
  %switch.i = icmp ult i64 %.off.i, -2
  br i1 %switch.i, label %3, label %numeric.operation__func_301.exit

3:                                                ; preds = %2
  %4 = or i64 %0, %1
  %5 = and i64 %4, -4294967296
  %6 = icmp eq i64 %5, 0
  br i1 %6, label %7, label %12

7:                                                ; preds = %3
  %8 = trunc i64 %1 to i32
  %9 = trunc i64 %0 to i32
  %10 = urem i32 %9, %8
  %11 = zext i32 %10 to i64
  br label %numeric.operation__func_301.exit

12:                                               ; preds = %3
  %13 = srem i64 %0, %1
  br label %numeric.operation__func_301.exit

numeric.operation__func_301.exit:                 ; preds = %7, %12, %2
  %common.ret.op.i = phi i64 [ 0, %2 ], [ %11, %7 ], [ %13, %12 ]
  ret i64 %common.ret.op.i
}

```

## numeric_shift

Symbols → `parity.baselineNumericShift` / `parity.baselineNumericShift`; baseline/wrapper machine code 51/51 bytes.

```asm
 push rbp
 mov rbp rsp
 cmp rsi 63
 jbe label1
 xor eax eax
 pop rbp
 ret
 mov rcx rsi
 mov rax rdi
 xor edx edx
 shld rdx rdi cl
 xor esi esi
 shl rax cl
 test cl 64
 cmovne rdx rax
 cmovne rax rsi
 test rdx rdx
 cmovne rax rsi
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericShift(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = icmp ugt i64 %1, 63
  br i1 %3, label %numeric.operation__func_299.exit, label %4

4:                                                ; preds = %2
  %5 = zext i64 %0 to i128
  %6 = zext nneg i64 %1 to i128
  %7 = shl nuw nsw i128 %5, %6
  %8 = icmp samesign ugt i128 %7, 18446744073709551615
  %9 = trunc nuw i128 %7 to i64
  %spec.select.i = select i1 %8, i64 0, i64 %9
  br label %numeric.operation__func_299.exit

numeric.operation__func_299.exit:                 ; preds = %2, %4
  %common.ret.op.i = phi i64 [ 0, %2 ], [ %spec.select.i, %4 ]
  ret i64 %common.ret.op.i
}

```

## numeric_saturating

Symbols → `parity.baselineNumericSaturating` / `parity.baselineNumericSaturating`; baseline/wrapper machine code 30/30 bytes.

```asm
 push rbp
 mov rbp rsp
 mov rax rdi
 mul rsi
 mov rcx -1
 cmovo rax rcx
 add rax rdi
 cmovb rax rcx
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericSaturating(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call i64 @llvm.umul.fix.sat.i64(i64 %0, i64 %1, i32 0)
  %4 = tail call i64 @llvm.uadd.sat.i64(i64 %3, i64 %0)
  ret i64 %4
}

```

## numeric_ranged

Symbols → `parity.baselineNumericRanged` / `parity.wrapperNumericRanged`; baseline/wrapper machine code 56/56 bytes.

```asm
 push rbp
 mov rbp rsp
 lea rax [rdi - 10001]
 cmp rax -10000
 jae label1
 xor eax eax
 pop rbp
 ret
 lea rax [rdi + rsi]
 lea rcx [rax - 10001]
 xor edx edx
 cmp rcx -10000
 cmovb rax rdx
 add rdi rsi
 cmovb rax rdx
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericRanged(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = add i64 %0, -10001
  %4 = icmp ult i64 %3, -10000
  br i1 %4, label %numeric.operation__func_294.exit, label %5

5:                                                ; preds = %2
  %6 = tail call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %0, i64 %1)
  %7 = extractvalue { i64, i1 } %6, 0
  %8 = extractvalue { i64, i1 } %6, 1
  %9 = add i64 %7, -10001
  %10 = icmp ult i64 %9, -10000
  %or.cond.i = or i1 %8, %10
  %spec.select.i = select i1 %or.cond.i, i64 0, i64 %7
  br label %numeric.operation__func_294.exit

numeric.operation__func_294.exit:                 ; preds = %2, %5
  %common.ret.op.i = phi i64 [ 0, %2 ], [ %spec.select.i, %5 ]
  ret i64 %common.ret.op.i
}

```

## numeric_cast

Symbols → `parity.baselineNumericCast` / `parity.baselineNumericCast`; baseline/wrapper machine code 25/25 bytes.

```asm
 push rbp
 mov rbp rsp
 movabs rax 4294967296
 cmp rdi rax
 cmovb rax rdi
 mov eax eax
 pop rbp
 ret
```

```llvm
define private range(i64 0, 4294967296) i64 @parity.baselineNumericCast(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call i64 @llvm.umin.i64(i64 %0, i64 4294967296)
  %common.ret.op.i = and i64 %3, 4294967295
  ret i64 %common.ret.op.i
}

```

## numeric_identity

Symbols → `parity.baselineNumericIdentity` / `parity.baselineNumericIdentity`; baseline/wrapper machine code 14/14 bytes.

```asm
 push rbp
 mov rbp rsp
 xor eax eax
 cmp rdi rsi
 sete al
 pop rbp
 ret
```

```llvm
define private range(i64 0, 2) i64 @parity.baselineNumericIdentity(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = icmp eq i64 %0, %1
  %4 = zext i1 %3 to i64
  ret i64 %4
}

```

## numeric_counter

Symbols → `parity.baselineNumericCounter` / `parity.wrapperNumericCounter`; baseline/wrapper machine code 15/15 bytes.

```asm
 push rbp
 mov rbp rsp
 xor eax eax
 inc rdi
 cmovne rax rdi
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericCounter(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %0, i64 1)
  %4 = extractvalue { i64, i1 } %3, 0
  %5 = extractvalue { i64, i1 } %3, 1
  %6 = select i1 %5, i64 0, i64 %4
  ret i64 %6
}

```

## numeric_count

Symbols → `parity.baselineNumericAdd` / `parity.wrapperNumericAdd`; baseline/wrapper machine code 15/15 bytes.

```asm
 push rbp
 mov rbp rsp
 xor eax eax
 add rdi rsi
 cmovae rax rdi
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericAdd(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %0, i64 %1)
  %4 = extractvalue { i64, i1 } %3, 0
  %5 = extractvalue { i64, i1 } %3, 1
  %6 = select i1 %5, i64 0, i64 %4
  ret i64 %6
}

```

## numeric_bits

Symbols → `parity.baselineNumericBits` / `parity.baselineNumericBits`; baseline/wrapper machine code 24/24 bytes.

```asm
 push rbp
 mov rbp rsp
 mov rax rdi
 shr rax 3
 and edi 7
 cmp rdi 1
 sbb rax -1
 pop rbp
 ret
```

```llvm
define private range(i64 0, 2305843009213693953) i64 @parity.baselineNumericBits(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = lshr i64 %0, 3
  %4 = and i64 %0, 7
  %5 = icmp ne i64 %4, 0
  %6 = zext i1 %5 to i64
  %7 = add nuw nsw i64 %3, %6
  ret i64 %7
}

```

## numeric_duration

Symbols → `parity.baselineNumericDuration` / `parity.wrapperNumericDuration`; baseline/wrapper machine code 23/23 bytes.

```asm
 push rbp
 mov rbp rsp
 mov rax rdi
 xor ecx ecx
 mov edx 1000000
 mul rdx
 cmovo rax rcx
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericDuration(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call { i64, i1 } @llvm.umul.with.overflow.i64(i64 %0, i64 1000000)
  %4 = extractvalue { i64, i1 } %3, 0
  %5 = extractvalue { i64, i1 } %3, 1
  %6 = select i1 %5, i64 0, i64 %4
  ret i64 %6
}

```

## numeric_rounding

Symbols → `parity.baselineNumericRounding` / `parity.baselineNumericRounding`; baseline/wrapper machine code 53/53 bytes.

```asm
 push rbp
 mov rbp rsp
 movabs rcx 2361183241434822607
 mov rax rdi
 imul rcx
 mov rax rdx
 shr rax 63
 sar rdx 7
 add rax rdx
 imul rcx rax 1000
 sub rdi rcx
 sar rdi 63
 add rax rdi
 pop rbp
 ret
```

```llvm
define private range(i64 -9223372036854776, 9223372036854776) i64 @parity.baselineNumericRounding(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = sdiv i64 %0, 1000
  %4 = srem i64 %0, 1000
  %.lobit.i = ashr i64 %4, 63
  %5 = add nsw i64 %.lobit.i, %3
  ret i64 %5
}

```

## numeric_instant

Symbols → `parity.baselineNumericAdd` / `parity.wrapperNumericAdd`; baseline/wrapper machine code 15/15 bytes.

```asm
 push rbp
 mov rbp rsp
 xor eax eax
 add rdi rsi
 cmovae rax rdi
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericAdd(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call { i64, i1 } @llvm.uadd.with.overflow.i64(i64 %0, i64 %1)
  %4 = extractvalue { i64, i1 } %3, 0
  %5 = extractvalue { i64, i1 } %3, 1
  %6 = select i1 %5, i64 0, i64 %4
  ret i64 %6
}

```

## numeric_invariant

Symbols → `parity.baselineNumericInvariant` / `parity.baselineNumericInvariant`; baseline/wrapper machine code 28/28 bytes.

```asm
 sub rsi rdi
 jb label1
 mov rax rsi
 ret
 push rbp
 mov rbp rsp
 mov edi offset .L__anon_1898
 mov esi 17
 call .Ldebug.defaultPanic
```

```llvm
define private i64 @parity.baselineNumericInvariant(i64 %0, i64 %1) unnamed_addr #7 {
  %3 = icmp ult i64 %1, %0
  br i1 %3, label %4, label %numeric.operation__func_259.exit

4:                                                ; preds = %2
  tail call fastcc void @debug.defaultPanic(ptr nonnull readonly align 1 @__anon_1898, i64 17)
  unreachable

numeric.operation__func_259.exit:                 ; preds = %2
  %5 = sub nuw i64 %1, %0
  ret i64 %5
}

```

## numeric_diagnostics

Symbols → `parity.baselineNumericDiagnostics` / `parity.baselineNumericDiagnostics`; baseline/wrapper machine code 12/12 bytes.

```asm
 push rbp
 mov rbp rsp
 mov rax rdi
 xor rax rsi
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericDiagnostics(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = xor i64 %1, %0
  ret i64 %3
}

```

## numeric_encoding

Symbols → `parity.baselineNumericEncoding` / `parity.baselineNumericEncoding`; baseline/wrapper machine code 12/12 bytes.

```asm
 push rbp
 mov rbp rsp
 mov rax rdi
 bswap rax
 pop rbp
 ret
```

```llvm
define private i64 @parity.baselineNumericEncoding(i64 %0, i64 %1) unnamed_addr #4 {
  %3 = tail call i64 @llvm.bswap.i64(i64 %0)
  ret i64 %3
}

```
