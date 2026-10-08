# aarch64-linux-gnu ReleaseFast parity

Zig 0.17.0, LLVM, baseline CPU, stripped object. All eleven pairs have identical emitted instructions (shared aliases or normalized assembly); storage/alignment assertions compile.

## secret_s32

Symbols → `parity.baselineSecretS32` / `parity.baselineSecretS32`; baseline/wrapper machine code 64/64 bytes.

```asm
 sub sp sp #32
 stp x29 x30 [sp #16]
 add x29 sp #16
 add x9 sp #8
 movi v0.2d #0000000000000000
 mov x8 x0
 stp x9 x0 [sp]
 mov x9 sp
 ldrb w9 [x0]
 ldrb w10 [x0 #31]
 str q0 [x0]
 eor w0 w10 w9
 str q0 [x8 #16]
 ldp x29 x30 [sp #16]
 add sp sp #32
 ret
```

```llvm
define private i8 @parity.baselineSecretS32(ptr nonnull align 1 %0) unnamed_addr #7 {
  %2 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #31
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

Symbols → `parity.baselineTransferS32` / `parity.baselineTransferS32`; baseline/wrapper machine code 120/120 bytes.

```asm
 sub sp sp #48
 stp x29 x30 [sp #32]
 add x29 sp #32
 sub x8 x29 #8
 stur x0 [x29 #-8]
 add x9 sp #16
 str x8 [sp #16]
 add x9 x0 #32
 cmp x1 x9
 b.hs label1
 add x9 x1 #32
 cmp x0 x9
 b.lo label2
 movi v0.2d #0000000000000000
 ldp q2 q1 [x0]
 stp q2 q1 [x1]
 str q0 [x0 #16]
 str q0 [x0]
 stur x1 [x29 #-8]
 str x8 [sp #8]
 add x8 sp #8
 ldrb w8 [x1]
 ldrb w9 [x1 #31]
 str q0 [x1]
 eor w0 w9 w8
 str q0 [x1 #16]
 ldp x29 x30 [sp #32]
 add sp sp #48
 ret
 bl ".Ldebug.FullPanic((function 'defaultPanic')).memcpyAlias"
```

```llvm
define private i8 @parity.baselineTransferS32(ptr nonnull align 1 %0, ptr nonnull align 1 %1) unnamed_addr #7 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %3) #31
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 32
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 32
  %7 = icmp uge ptr %1, %5
  %8 = icmp uge ptr %0, %6
  %9 = or i1 %7, %8
  br i1 %9, label %cases.transfer__func_302.exit, label %10

10:                                               ; preds = %2
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable

cases.transfer__func_302.exit:                    ; preds = %2
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %1, ptr noundef nonnull align 1 dereferenceable(32) %0, i64 32, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %0, i8 0, i64 32, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %1, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %3) #31
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

Symbols → `parity.baselineSecretS48` / `parity.baselineSecretS48`; baseline/wrapper machine code 68/68 bytes.

```asm
 sub sp sp #32
 stp x29 x30 [sp #16]
 add x29 sp #16
 add x9 sp #8
 movi v0.2d #0000000000000000
 mov x8 x0
 stp x9 x0 [sp]
 mov x9 sp
 ldrb w9 [x0]
 ldrb w10 [x0 #47]
 str q0 [x0 #16]
 str q0 [x0]
 eor w0 w10 w9
 str q0 [x8 #32]
 ldp x29 x30 [sp #16]
 add sp sp #32
 ret
```

```llvm
define private i8 @parity.baselineSecretS48(ptr nonnull align 1 %0) unnamed_addr #7 {
  %2 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #31
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

Symbols → `parity.baselineTransferS48` / `parity.baselineTransferS48`; baseline/wrapper machine code 136/136 bytes.

```asm
 sub sp sp #48
 stp x29 x30 [sp #32]
 add x29 sp #32
 sub x8 x29 #8
 stur x0 [x29 #-8]
 add x9 sp #16
 str x8 [sp #16]
 add x9 x0 #48
 cmp x1 x9
 b.hs label1
 add x9 x1 #48
 cmp x0 x9
 b.lo label2
 movi v1.2d #0000000000000000
 ldp q2 q0 [x0 #16]
 ldr q3 [x0]
 stp q2 q0 [x1 #16]
 str q3 [x1]
 str q1 [x0 #16]
 str q1 [x0 #32]
 str q1 [x0]
 stur x1 [x29 #-8]
 str x8 [sp #8]
 add x8 sp #8
 ldrb w8 [x1]
 ldrb w9 [x1 #47]
 str q1 [x1 #16]
 str q1 [x1]
 eor w0 w9 w8
 str q1 [x1 #32]
 ldp x29 x30 [sp #32]
 add sp sp #48
 ret
 bl ".Ldebug.FullPanic((function 'defaultPanic')).memcpyAlias"
```

```llvm
define private i8 @parity.baselineTransferS48(ptr nonnull align 1 %0, ptr nonnull align 1 %1) unnamed_addr #7 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %3) #31
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 48
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 48
  %7 = icmp uge ptr %1, %5
  %8 = icmp uge ptr %0, %6
  %9 = or i1 %7, %8
  br i1 %9, label %cases.transfer__func_295.exit, label %10

10:                                               ; preds = %2
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable

cases.transfer__func_295.exit:                    ; preds = %2
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %1, ptr noundef nonnull align 1 dereferenceable(48) %0, i64 48, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %0, i8 0, i64 48, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %1, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %3) #31
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

Symbols → `parity.baselineSecretMaterial` / `parity.baselineSecretMaterial`; baseline/wrapper machine code 68/68 bytes.

```asm
 sub sp sp #48
 stp x29 x30 [sp #16]
 stp x20 x19 [sp #32]
 add x29 sp #16
 add x8 sp #8
 mov w1 wzr
 mov w2 #1056
 stp x8 x0 [sp]
 mov x8 sp
 ldrb w19 [x0 #16]
 ldrb w20 [x0 #536]
 bl memset
 eor w0 w20 w19
 ldp x20 x19 [sp #32]
 ldp x29 x30 [sp #16]
 add sp sp #48
 ret
```

```llvm
define private i8 @parity.baselineSecretMaterial(ptr nonnull align 8 %0) unnamed_addr #7 {
  %2 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #31
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

Symbols → `parity.baselineTransferMaterial` / `parity.baselineTransferMaterial`; baseline/wrapper machine code 164/164 bytes.

```asm
 sub sp sp #64
 stp x29 x30 [sp #16]
 str x21 [sp #32]
 stp x20 x19 [sp #48]
 add x29 sp #16
 add x21 x29 #24
 str x0 [x29 #24]
 add x8 sp #8
 str x21 [sp #8]
 mov x19 x1
 mov x20 x0
 add x8 x0 #1056
 cmp x1 x8
 b.hs label1
 add x8 x19 #1056
 cmp x20 x8
 b.lo label2
 mov x0 x19
 mov x1 x20
 mov w2 #1056
 bl memcpy
 mov x0 x20
 mov w1 wzr
 mov w2 #1056
 bl memset
 str x19 [x29 #24]
 mov x8 sp
 mov x0 x19
 str x21 [sp]
 mov w1 wzr
 mov w2 #1056
 ldrb w20 [x19 #16]
 ldrb w21 [x19 #536]
 bl memset
 eor w0 w21 w20
 ldp x20 x19 [sp #48]
 ldr x21 [sp #32]
 ldp x29 x30 [sp #16]
 add sp sp #64
 ret
 bl ".Ldebug.FullPanic((function 'defaultPanic')).memcpyAlias"
```

```llvm
define private i8 @parity.baselineTransferMaterial(ptr nonnull align 8 %0, ptr nonnull align 8 %1) unnamed_addr #7 {
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %0, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %3) #31
  call void @llvm.lifetime.end.p0(ptr nonnull %3)
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 1056
  %6 = getelementptr inbounds nuw i8, ptr %1, i64 1056
  %7 = icmp uge ptr %1, %5
  %8 = icmp uge ptr %0, %6
  %9 = or i1 %7, %8
  br i1 %9, label %cases.transfer__func_289.exit, label %10

10:                                               ; preds = %2
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable

cases.transfer__func_289.exit:                    ; preds = %2
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(1056) %1, ptr noundef nonnull align 8 dereferenceable(1056) %0, i64 1056, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 8 %0, i8 0, i64 1056, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %3)
  store ptr %1, ptr %3, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %3) #31
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

Symbols → `parity.baselineCleanup` / `parity.baselineCleanup`; baseline/wrapper machine code 64/64 bytes.

```asm
 sub sp sp #80
 stp x29 x30 [sp #64]
 add x29 sp #64
 movi v0.2d #0000000000000000
 tst w0 #0x1
 sturb wzr [x29 #-4]
 strb wzr [sp #46]
 csinc w0 w1 wzr eq
 strh wzr [sp #44]
 str wzr [sp #40]
 str xzr [sp #32]
 str q0 [sp #16]
 str q0 [sp]
 ldp x29 x30 [sp #64]
 add sp sp #80
 ret
```

```llvm
define private i8 @parity.baselineCleanup(i1 %0, i8 %1) unnamed_addr #25 {
  %.sroa.0.i = alloca i8, align 4
  %.sroa.4.i = alloca [47 x i8], align 4
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.0.i)
  call void @llvm.lifetime.start.p0(ptr nonnull %.sroa.4.i)
  call void @llvm.memset.p0.i64(ptr align 4 %.sroa.0.i, i8 0, i64 1, i1 true)
  call void @llvm.memset.p0.i64(ptr align 4 %.sroa.4.i, i8 0, i64 47, i1 true)
  %..i = select i1 %0, i8 1, i8 %1
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.0.i)
  call void @llvm.lifetime.end.p0(ptr nonnull %.sroa.4.i)
  ret i8 %..i
}

```

## cleanup_material

Symbols → `parity.baselineCleanupMaterial` / `parity.baselineCleanupMaterial`; baseline/wrapper machine code 240/240 bytes.

```asm
 stp x29 x30 [sp #-48]!
 str x28 [sp #16]
 stp x20 x19 [sp #32]
 mov x29 sp
 sub sp sp #1072
 movi v0.2d #0000000000000000
 mov w19 w1
 mov w20 w0
 add x8 sp #544
 add x0 sp #16
 mov w1 wzr
 mov w2 #511
 str xzr [x8 #520]
 str xzr [x8 #512]
 str q0 [x8 #496]
 str q0 [x8 #480]
 str q0 [x8 #464]
 str q0 [x8 #448]
 str q0 [x8 #432]
 str q0 [x8 #416]
 str q0 [x8 #400]
 str q0 [x8 #384]
 str q0 [x8 #368]
 str q0 [x8 #352]
 str q0 [x8 #336]
 str q0 [x8 #320]
 str q0 [x8 #304]
 str q0 [x8 #288]
 str q0 [x8 #272]
 str q0 [x8 #256]
 str q0 [x8 #240]
 str q0 [x8 #224]
 str q0 [x8 #208]
 str q0 [x8 #192]
 str q0 [x8 #176]
 str q0 [x8 #160]
 str q0 [x8 #144]
 str q0 [x8 #128]
 str q0 [x8 #112]
 str q0 [x8 #96]
 str q0 [x8 #80]
 str q0 [x8 #64]
 str q0 [x8 #48]
 str q0 [x8 #32]
 str q0 [x8 #16]
 str q0 [x8]
 str xzr [sp #536]
 strb wzr [sp #528]
 bl memset
 tst w20 #0x1
 strb wzr [sp #12]
 str wzr [sp #4]
 csinc w0 w19 wzr eq
 strb wzr [sp #10]
 strh wzr [sp #8]
 add sp sp #1072
 ldp x20 x19 [sp #32]
 ldr x28 [sp #16]
 ldp x29 x30 [sp] #48
 ret
```

```llvm
define private i8 @parity.baselineCleanupMaterial(i1 %0, i8 %1) unnamed_addr #2 {
  %.sroa.0.sroa.0.i = alloca i64, align 8
  %.sroa.0.sroa.3.i = alloca i64, align 8
  %.sroa.0.sroa.4.i = alloca [512 x i8], align 8
  %.sroa.0.sroa.5.i = alloca i64, align 8
  %.sroa.31.i = alloca i8, align 8
  %.sroa.4.sroa.0.i = alloca [511 x i8], align 4
  %.sroa.4.sroa.3.i = alloca i8, align 4
  %.sroa.4.sroa.4.i = alloca [7 x i8], align 4
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
  call void @llvm.memset.p0.i64(ptr align 8 %.sroa.31.i, i8 0, i64 1, i1 true)
  call void @llvm.memset.p0.i64(ptr align 4 %.sroa.4.sroa.0.i, i8 0, i64 511, i1 true)
  call void @llvm.memset.p0.i64(ptr align 4 %.sroa.4.sroa.3.i, i8 0, i64 1, i1 true)
  call void @llvm.memset.p0.i64(ptr align 4 %.sroa.4.sroa.4.i, i8 0, i64 7, i1 true)
  %..i = select i1 %0, i8 1, i8 %1
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

Symbols → `parity.baselineBudget` / `parity.baselineBudget`; baseline/wrapper machine code 340/340 bytes.

```asm
 sub sp sp #48
 stp x29 x30 [sp #32]
 add x29 sp #32
 add x9 x0 #16
 ldaxrb w8 [x9]
 cbnz x8 label7
 mov w8 #1
 stxrb w10 w8 [x9]
 cbnz w10 label8
 sub x8 x29 #8
 stur x0 [x29 #-8]
 str x8 [sp #16]
 add x8 sp #16
 ldr x10 [x0]
 cmp x10 #63
 b.ls label3
 mov w8 wzr
 mov w0 w8
 stlrb wzr [x9]
 ldp x29 x30 [sp #32]
 add sp sp #48
 ret
 ldr x11 [x0 #8]
 mov w12 #16777216
 mov w8 wzr
 cmp x11 x12
 b.hi label2
 sub x12 x12 x11
 cmp x1 x12
 b.hi label2
 add x8 x10 #1
 add x10 x11 x1
 stur x0 [x29 #-8]
 stp x8 x10 [x0]
 sub x8 x29 #8
 add x11 x0 #16
 str x8 [sp #8]
 add x10 sp #8
 stlrb wzr [x11]
 ldaxrb w8 [x9]
 cbnz x8 label10
 mov w8 #1
 stxrb w10 w8 [x9]
 cbnz w10 label11
 ldr x8 [x0 #8]
 cmp x8 x1
 b.lo label5
 ldr x10 [x0]
 cbz x10 label5
 sub x10 x10 #1
 subs x8 x8 x1
 str x10 [x0]
 b.lo label6
 str x8 [x0 #8]
 sub x8 x29 #8
 mov x10 sp
 stur x0 [x29 #-8]
 str x8 [sp]
 mov w8 #1
 mov w0 w8
 stlrb wzr [x9]
 ldp x29 x30 [sp #32]
 add sp sp #48
 ret
 adrp x0 .L__anon_15283
 add x0 x0 :lo12:.L__anon_15283
 mov w1 #36
 bl .Ldebug.defaultPanic
 bl ".Ldebug.FullPanic((function 'defaultPanic')).integerOverflow"
 clrex
 mov w8 #1
 isb
 ldaxrb w10 [x9]
 cbnz x10 label7
 stxrb w10 w8 [x9]
 cbz w10 label1
 b label9
 clrex
 mov w8 #1
 isb
 ldaxrb w10 [x9]
 cbnz x10 label10
 stxrb w10 w8 [x9]
 cbz w10 label4
 b label12
```

```llvm
define private noundef i1 @parity.baselineBudget(ptr nonnull align 8 %0, i64 %1) unnamed_addr #7 {
cmpxchg.start:
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = getelementptr inbounds nuw i8, ptr %0, i64 16
  %6 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %5)
  %7 = trunc i64 %6 to i8
  %should_store = icmp eq i8 %7, 0
  br i1 %should_store, label %cmpxchg.trystore, label %.lr.ph.i.i.sink.split, !prof !28

cmpxchg.trystore:                                 ; preds = %cmpxchg.start
  %8 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %5)
  %success = icmp eq i32 %8, 0
  br i1 %success, label %cases.lock__func_284.exit.i, label %.lr.ph.i.i.preheader, !prof !28

.lr.ph.i.i.sink.split:                            ; preds = %.lr.ph.i.i, %cmpxchg.start
  call void @llvm.aarch64.clrex()
  br label %.lr.ph.i.i.preheader

.lr.ph.i.i.preheader:                             ; preds = %cmpxchg.trystore, %.lr.ph.i.i.sink.split
  br label %.lr.ph.i.i

.lr.ph.i.i:                                       ; preds = %.lr.ph.i.i.preheader, %cmpxchg.trystore11
  tail call void asm sideeffect "isb", ""() #31
  %9 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %5)
  %10 = trunc i64 %9 to i8
  %should_store14 = icmp eq i8 %10, 0
  br i1 %should_store14, label %cmpxchg.trystore11, label %.lr.ph.i.i.sink.split, !prof !28

cmpxchg.trystore11:                               ; preds = %.lr.ph.i.i
  %11 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %5)
  %success16 = icmp eq i32 %11, 0
  br i1 %success16, label %cases.lock__func_284.exit.i, label %.lr.ph.i.i, !prof !28

cases.lock__func_284.exit.i:                      ; preds = %cmpxchg.trystore11, %cmpxchg.trystore
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #31
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %12 = load i64, ptr %0, align 8
  %13 = icmp ugt i64 %12, 63
  br i1 %13, label %cases.budget__func_283.exit, label %14

14:                                               ; preds = %cases.lock__func_284.exit.i
  %15 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %16 = load i64, ptr %15, align 8
  %17 = icmp ugt i64 %16, 16777216
  %18 = sub nuw nsw i64 16777216, %16
  %19 = icmp ugt i64 %1, %18
  %or.cond.i.i = select i1 %17, i1 true, i1 %19
  br i1 %or.cond.i.i, label %cases.budget__func_283.exit, label %cmpxchg.start28

cmpxchg.start28:                                  ; preds = %14
  %20 = add nuw nsw i64 %12, 1
  store i64 %20, ptr %0, align 8
  %21 = add nuw nsw i64 %16, %1
  %sunkaddr = getelementptr inbounds i8, ptr %0, i64 8
  store i64 %21, ptr %sunkaddr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #31
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %sunkaddr53 = getelementptr inbounds i8, ptr %0, i64 16
  store atomic i8 0, ptr %sunkaddr53 release, align 8
  %22 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %5)
  %23 = trunc i64 %22 to i8
  %should_store29 = icmp eq i8 %23, 0
  br i1 %should_store29, label %cmpxchg.trystore26, label %.lr.ph.i8.i.sink.split, !prof !28

cmpxchg.trystore26:                               ; preds = %cmpxchg.start28
  %24 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %5)
  %success31 = icmp eq i32 %24, 0
  br i1 %success31, label %cases.lock__func_284.exit9.i, label %.lr.ph.i8.i.preheader, !prof !28

.lr.ph.i8.i.sink.split:                           ; preds = %.lr.ph.i8.i, %cmpxchg.start28
  call void @llvm.aarch64.clrex()
  br label %.lr.ph.i8.i.preheader

.lr.ph.i8.i.preheader:                            ; preds = %cmpxchg.trystore26, %.lr.ph.i8.i.sink.split
  br label %.lr.ph.i8.i

.lr.ph.i8.i:                                      ; preds = %.lr.ph.i8.i.preheader, %cmpxchg.trystore41
  call void asm sideeffect "isb", ""() #31
  %25 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %5)
  %26 = trunc i64 %25 to i8
  %should_store44 = icmp eq i8 %26, 0
  br i1 %should_store44, label %cmpxchg.trystore41, label %.lr.ph.i8.i.sink.split, !prof !28

cmpxchg.trystore41:                               ; preds = %.lr.ph.i8.i
  %27 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %5)
  %success46 = icmp eq i32 %27, 0
  br i1 %success46, label %cases.lock__func_284.exit9.i, label %.lr.ph.i8.i, !prof !28

cases.lock__func_284.exit9.i:                     ; preds = %cmpxchg.trystore41, %cmpxchg.trystore26
  %sunkaddr54 = getelementptr inbounds i8, ptr %0, i64 8
  %28 = load i64, ptr %sunkaddr54, align 8
  %29 = icmp ult i64 %28, %1
  br i1 %29, label %.critedge.i.i, label %30

30:                                               ; preds = %cases.lock__func_284.exit9.i
  %31 = load i64, ptr %0, align 8
  %32 = icmp eq i64 %31, 0
  br i1 %32, label %.critedge.i.i, label %33

.critedge.i.i:                                    ; preds = %30, %cases.lock__func_284.exit9.i
  call fastcc void @debug.defaultPanic(ptr nonnull readonly align 1 @__anon_15283, i64 36)
  unreachable

33:                                               ; preds = %30
  %34 = add i64 %31, -1
  store i64 %34, ptr %0, align 8
  %35 = call { i64, i1 } @llvm.usub.with.overflow.i64(i64 %28, i64 %1)
  %36 = extractvalue { i64, i1 } %35, 1
  br i1 %36, label %37, label %cases.uncharge.exit.i

37:                                               ; preds = %33
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).integerOverflow"()
  unreachable

cases.uncharge.exit.i:                            ; preds = %33
  %38 = extractvalue { i64, i1 } %35, 0
  %sunkaddr55 = getelementptr inbounds i8, ptr %0, i64 8
  store i64 %38, ptr %sunkaddr55, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #31
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  br label %cases.budget__func_283.exit

cases.budget__func_283.exit:                      ; preds = %cases.lock__func_284.exit.i, %14, %cases.uncharge.exit.i
  %common.ret.op.i11.i = phi i1 [ true, %cases.uncharge.exit.i ], [ false, %14 ], [ false, %cases.lock__func_284.exit.i ]
  store atomic i8 0, ptr %5 release, align 8
  ret i1 %common.ret.op.i11.i
}

```

## job

Symbols → `parity.baselineJob` / `parity.baselineJob`; baseline/wrapper machine code 228/228 bytes.

```asm
 sub sp sp #48
 stp x29 x30 [sp #32]
 add x29 sp #32
 add x8 x0 #24
 ldaxrb w9 [x8]
 cbnz x9 label4
 mov w9 #1
 stxrb w10 w9 [x8]
 cbnz w10 label5
 mov w9 #1
 str x1 [x0]
 add x11 x0 #24
 strb w9 [x0 #8]
 add x10 sp #16
 strb w9 [x0 #16]
 sub x9 x29 #8
 stur x0 [x29 #-8]
 str x9 [sp #16]
 stlrb wzr [x11]
 ldaxrb w9 [x8]
 cbnz x9 label7
 mov w9 #1
 stxrb w10 w9 [x8]
 cbnz w10 label8
 ldrb w8 [x0 #8]
 tbz w8 #0 label3
 mov w9 #2
 ldr x8 [x0]
 stp xzr xzr [x0]
 strb w9 [x0 #16]
 sub x9 x29 #8
 stur x0 [x29 #-8]
 str x9 [sp #8]
 add x9 sp #8
 add x9 x0 #24
 mov x0 x8
 stlrb wzr [x9]
 ldp x29 x30 [sp #32]
 add sp sp #48
 ret
 bl ".Ldebug.FullPanic((function 'defaultPanic')).unwrapNull"
 clrex
 mov w9 #1
 isb
 ldaxrb w10 [x8]
 cbnz x10 label4
 stxrb w10 w9 [x8]
 cbz w10 label1
 b label6
 clrex
 mov w9 #1
 isb
 ldaxrb w10 [x8]
 cbnz x10 label7
 stxrb w10 w9 [x8]
 cbz w10 label2
 b label9
```

```llvm
define private i64 @parity.baselineJob(ptr nonnull align 8 %0, i64 %1) unnamed_addr #7 {
cmpxchg.start:
  %2 = alloca ptr, align 8
  %3 = alloca ptr, align 8
  %4 = getelementptr inbounds nuw i8, ptr %0, i64 24
  %5 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %4)
  %6 = trunc i64 %5 to i8
  %should_store = icmp eq i8 %6, 0
  br i1 %should_store, label %cmpxchg.trystore, label %.lr.ph.i.i.sink.split, !prof !28

cmpxchg.trystore:                                 ; preds = %cmpxchg.start
  %7 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %4)
  %success = icmp eq i32 %7, 0
  br i1 %success, label %cases.lock__func_282.exit.i, label %.lr.ph.i.i.preheader, !prof !28

.lr.ph.i.i.sink.split:                            ; preds = %.lr.ph.i.i, %cmpxchg.start
  call void @llvm.aarch64.clrex()
  br label %.lr.ph.i.i.preheader

.lr.ph.i.i.preheader:                             ; preds = %cmpxchg.trystore, %.lr.ph.i.i.sink.split
  br label %.lr.ph.i.i

.lr.ph.i.i:                                       ; preds = %.lr.ph.i.i.preheader, %cmpxchg.trystore7
  tail call void asm sideeffect "isb", ""() #31
  %8 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %4)
  %9 = trunc i64 %8 to i8
  %should_store10 = icmp eq i8 %9, 0
  br i1 %should_store10, label %cmpxchg.trystore7, label %.lr.ph.i.i.sink.split, !prof !28

cmpxchg.trystore7:                                ; preds = %.lr.ph.i.i
  %10 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %4)
  %success12 = icmp eq i32 %10, 0
  br i1 %success12, label %cases.lock__func_282.exit.i, label %.lr.ph.i.i, !prof !28

cases.lock__func_282.exit.i:                      ; preds = %cmpxchg.trystore7, %cmpxchg.trystore
  store i64 %1, ptr %0, align 8
  %.sroa.2.0..0..sroa_idx.i = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i8 1, ptr %.sroa.2.0..0..sroa_idx.i, align 8
  %11 = getelementptr inbounds nuw i8, ptr %0, i64 16
  store i8 1, ptr %11, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #31
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %sunkaddr = getelementptr inbounds i8, ptr %0, i64 24
  store atomic i8 0, ptr %sunkaddr release, align 8
  %12 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %4)
  %13 = trunc i64 %12 to i8
  %should_store25 = icmp eq i8 %13, 0
  br i1 %should_store25, label %cmpxchg.trystore22, label %.lr.ph.i14.i.sink.split, !prof !28

cmpxchg.trystore22:                               ; preds = %cases.lock__func_282.exit.i
  %14 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %4)
  %success27 = icmp eq i32 %14, 0
  br i1 %success27, label %cases.lock__func_282.exit15.i, label %.lr.ph.i14.i.preheader, !prof !28

.lr.ph.i14.i.sink.split:                          ; preds = %.lr.ph.i14.i, %cases.lock__func_282.exit.i
  call void @llvm.aarch64.clrex()
  br label %.lr.ph.i14.i.preheader

.lr.ph.i14.i.preheader:                           ; preds = %cmpxchg.trystore22, %.lr.ph.i14.i.sink.split
  br label %.lr.ph.i14.i

.lr.ph.i14.i:                                     ; preds = %.lr.ph.i14.i.preheader, %cmpxchg.trystore37
  call void asm sideeffect "isb", ""() #31
  %15 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %4)
  %16 = trunc i64 %15 to i8
  %should_store40 = icmp eq i8 %16, 0
  br i1 %should_store40, label %cmpxchg.trystore37, label %.lr.ph.i14.i.sink.split, !prof !28

cmpxchg.trystore37:                               ; preds = %.lr.ph.i14.i
  %17 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %4)
  %success42 = icmp eq i32 %17, 0
  br i1 %success42, label %cases.lock__func_282.exit15.i, label %.lr.ph.i14.i, !prof !28

cases.lock__func_282.exit15.i:                    ; preds = %cmpxchg.trystore37, %cmpxchg.trystore22
  %sunkaddr49 = getelementptr inbounds i8, ptr %0, i64 8
  %.sroa.211.0.copyload.i = load i8, ptr %sunkaddr49, align 8
  %18 = trunc nuw i8 %.sroa.211.0.copyload.i to i1
  br i1 %18, label %cases.job__func_281.exit, label %19

19:                                               ; preds = %cases.lock__func_282.exit15.i
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).unwrapNull"()
  unreachable

cases.job__func_281.exit:                         ; preds = %cases.lock__func_282.exit15.i
  %.sroa.010.0.copyload.i = load i64, ptr %0, align 8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %0, i8 0, i64 16, i1 false)
  %sunkaddr50 = getelementptr inbounds i8, ptr %0, i64 16
  store i8 2, ptr %sunkaddr50, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %0, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #31
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %sunkaddr51 = getelementptr inbounds i8, ptr %0, i64 24
  store atomic i8 0, ptr %sunkaddr51 release, align 8
  ret i64 %.sroa.010.0.copyload.i
}

```

## increment

Symbols → `parity.baselineIncrement` / `parity.baselineIncrement`; baseline/wrapper machine code 88/88 bytes.

```asm
 stp x29 x30 [sp #-16]!
 mov x29 sp
 add x8 x0 #8
 ldaxrb w9 [x8]
 cbnz x9 label2
 mov w9 #1
 stxrb w10 w9 [x8]
 cbnz w10 label3
 ldr x8 [x0]
 add x8 x8 #1
 str x8 [x0] #8
 stlrb wzr [x0]
 ldp x29 x30 [sp] #16
 ret
 clrex
 mov w9 #1
 isb
 ldaxrb w10 [x8]
 cbnz x10 label2
 stxrb w10 w9 [x8]
 cbz w10 label1
 b label4
```

```llvm
define private void @parity.baselineIncrement(ptr nonnull align 8 captures(none) %0) unnamed_addr #7 {
cmpxchg.start:
  %1 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %2 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %1)
  %3 = trunc i64 %2 to i8
  %should_store = icmp eq i8 %3, 0
  br i1 %should_store, label %cmpxchg.trystore, label %.lr.ph.i.i.sink.split, !prof !28

cmpxchg.trystore:                                 ; preds = %cmpxchg.start
  %4 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %1)
  %success = icmp eq i32 %4, 0
  br i1 %success, label %cases.increment__func_279.exit, label %.lr.ph.i.i.preheader, !prof !28

.lr.ph.i.i.sink.split:                            ; preds = %.lr.ph.i.i, %cmpxchg.start
  call void @llvm.aarch64.clrex()
  br label %.lr.ph.i.i.preheader

.lr.ph.i.i.preheader:                             ; preds = %cmpxchg.trystore, %.lr.ph.i.i.sink.split
  br label %.lr.ph.i.i

.lr.ph.i.i:                                       ; preds = %.lr.ph.i.i.preheader, %cmpxchg.trystore7
  tail call void asm sideeffect "isb", ""() #31
  %5 = call i64 @llvm.aarch64.ldaxr.p0(ptr elementtype(i8) %1)
  %6 = trunc i64 %5 to i8
  %should_store10 = icmp eq i8 %6, 0
  br i1 %should_store10, label %cmpxchg.trystore7, label %.lr.ph.i.i.sink.split, !prof !28

cmpxchg.trystore7:                                ; preds = %.lr.ph.i.i
  %7 = call i32 @llvm.aarch64.stxr.p0(i64 1, ptr elementtype(i8) %1)
  %success12 = icmp eq i32 %7, 0
  br i1 %success12, label %cases.increment__func_279.exit, label %.lr.ph.i.i, !prof !28

cases.increment__func_279.exit:                   ; preds = %cmpxchg.trystore7, %cmpxchg.trystore
  %8 = load i64, ptr %0, align 8
  %9 = add i64 %8, 1
  store i64 %9, ptr %0, align 8
  %sunkaddr = getelementptr inbounds i8, ptr %0, i64 8
  store atomic i8 0, ptr %sunkaddr release, align 8
  ret void
}

```
