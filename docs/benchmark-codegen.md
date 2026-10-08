# Optimized benchmark body evidence

Zig 0.17.0, native aarch64-macos, LLVM ReleaseFast; same source/modules as `zig build bench`. Compiler flags: `-Ofast -fllvm`, no stripping. Timing loops are noinline. The 20 source A/B instantiations emit ten measure bodies: both labels call the identical body for each row. All transfers and volatile erasures remain; observation barriers prevent constant-folded payloads and discarded copies. Io/group setup is the same for both contention labels.

LLVM IR SHA-256: `9788c6149fea98705674b28c3c7827b86d66e04c6852895439b5c5303cee0492`. Source SHA-256: bench/owners.zig `54dcda63017173e2e4149211aee71d4fc0dc08a9c80cf0b89a1fcfd92d344c28`; ci/cases.zig `29794ca510113d4d29ebbecdc176f7418c775196adab1148e49c902b833fc4c2`.

| Row | Shared body | Calls from A/B/warmup/smoke |
|---|---|---:|
| secret32 | `owners.measure__func_21` | 8 |
| transfer32 | `owners.measure__func_48` | 8 |
| secret48 | `owners.measure__func_50` | 8 |
| transfer48 | `owners.measure__func_56` | 8 |
| material | `owners.measure__func_58` | 8 |
| transferMaterial | `owners.measure__func_60` | 8 |
| budget | `owners.measure__func_62` | 8 |
| job | `owners.measure__func_64` | 8 |
| contention2 | `owners.measure__func_66` | 8 |
| contention8 | `owners.measure__func_68` | 8 |

## owners.measure__func_21

```llvm
Block:
  %2 = alloca %Io.Timestamp, align 16
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca %Io.Timestamp, align 16
  %8 = alloca [32 x i8], align 1
  %9 = alloca [32 x i8], align 1
  %10 = alloca %Material.Material, align 16
  %11 = getelementptr i8, ptr %.8.val, i64 704
  %.val23.val = load ptr, ptr %11, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %12 = icmp eq ptr @__anon_2651, @__anon_2661
  %13 = getelementptr inbounds nuw i8, ptr %9, i64 32
  %14 = getelementptr inbounds nuw i8, ptr %8, i64 32
  %15 = icmp uge ptr %8, %13
  %16 = icmp uge ptr %9, %14
  %17 = or i1 %16, %15
  %18 = getelementptr inbounds nuw i8, ptr %10, i64 16
  %19 = getelementptr inbounds nuw i8, ptr %10, i64 536
  br i1 %12, label %Else6.us.preheader, label %Block.split

Else6.us.preheader:                               ; preds = %Block
  br label %Else6.us

Else6.us:                                         ; preds = %Else6.us.preheader, %Else6.us
  %.19.us = phi i64 [ %.2.us, %Else6.us ], [ 0, %Else6.us.preheader ]
  %.0158.us = phi i64 [ %23, %Else6.us ], [ 0, %Else6.us.preheader ]
  %20 = trunc i64 %.0158.us to i8
  %sunkaddr = getelementptr inbounds i8, ptr %10, i64 1048
  store i8 0, ptr %sunkaddr, align 8
  store <2 x i64> <i64 256, i64 3>, ptr %10, align 16
  %sunkaddr33 = getelementptr inbounds i8, ptr %10, i64 16
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 16 dereferenceable(512) %18, i8 %20, i64 512, i1 false)
  %21 = xor i8 %20, 81
  %sunkaddr34 = getelementptr inbounds i8, ptr %10, i64 536
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(512) %19, i8 %21, i64 512, i1 false)
  %sunkaddr32 = getelementptr inbounds i8, ptr %10, i64 528
  store i64 0, ptr %sunkaddr32, align 16
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %10, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i.us = load i8, ptr %sunkaddr33, align 16
  %.val1.i.us = load i8, ptr %sunkaddr34, align 8
  %22 = xor i8 %.val1.i.us, %.val.i.us
  call void @llvm.memset.p0.i64(ptr nonnull align 16 %10, i8 0, i64 1056, i1 true)
  %.pn.us = zext i8 %22 to i64
  %.2.us = add i64 %.19.us, %.pn.us
  %23 = add nuw nsw i64 %.0158.us, 1
  %exitcond23.not = icmp eq i64 %1, %23
  br i1 %exitcond23.not, label %common.ret, label %Else6.us

Block.split:                                      ; preds = %Block
  %24 = icmp eq ptr @__anon_2651, @__anon_3162
  br i1 %24, label %Block.split.split.us, label %Else6.preheader

Else6.preheader:                                  ; preds = %Block.split
  br label %Else6

Block.split.split.us:                             ; preds = %Block.split
  %.fr = freeze i1 %17
  br i1 %.fr, label %Else6.us10.us.preheader, label %Else6.us10

Else6.us10.us.preheader:                          ; preds = %Block.split.split.us
  br label %Else6.us10.us

Else6.us10.us:                                    ; preds = %Else6.us10.us.preheader, %Else6.us10.us
  %.19.us11.us = phi i64 [ %.2.us16.us, %Else6.us10.us ], [ 0, %Else6.us10.us.preheader ]
  %.0158.us12.us = phi i64 [ %29, %Else6.us10.us ], [ 0, %Else6.us10.us.preheader ]
  %25 = trunc i64 %.0158.us12.us to i8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %9, i8 %25, i64 32, i1 false)
  %26 = load i8, ptr %9, align 1
  %27 = xor i8 %26, 81
  store i8 %27, ptr %9, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %9, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %8, ptr noundef nonnull align 1 dereferenceable(32) %9, i64 32, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %9, i8 0, i64 32, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %8, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i61.us.us = load i8, ptr %8, align 1
  %sunkaddr35 = getelementptr inbounds i8, ptr %8, i64 31
  %.val1.i62.us.us = load i8, ptr %sunkaddr35, align 1
  %28 = xor i8 %.val1.i62.us.us, %.val.i61.us.us
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %8, i8 0, i64 32, i1 true)
  %.pn.us15.us = zext i8 %28 to i64
  %.2.us16.us = add i64 %.19.us11.us, %.pn.us15.us
  %29 = add nuw nsw i64 %.0158.us12.us, 1
  %exitcond22.not = icmp eq i64 %1, %29
  br i1 %exitcond22.not, label %common.ret, label %Else6.us10.us

Else6.us10:                                       ; preds = %Block.split.split.us
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %9, i8 0, i64 32, i1 false)
  store i8 81, ptr %9, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %9, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable

common.ret:                                       ; preds = %Else6, %Else6.us10.us, %Else6.us
  %.us-phi = phi i64 [ %.2.us, %Else6.us ], [ %.2.us16.us, %Else6.us10.us ], [ %.2, %Else6 ]
  %sunkaddr36 = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr36, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %30 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %31 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %32 = sub nsw i96 %30, %31
  call void asm sideeffect "", "r"(i64 %.us-phi) #47
  %33 = sitofp i96 %32 to double
  %34 = uitofp nneg i64 %1 to double
  %35 = fdiv double %33, %34
  store double %35, ptr %0, align 8
  %.sroa.213.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.213.0..sroa_idx, align 8
  ret void

Else6:                                            ; preds = %Else6.preheader, %Else6
  %.19 = phi i64 [ %.2, %Else6 ], [ 0, %Else6.preheader ]
  %.0158 = phi i64 [ %40, %Else6 ], [ 0, %Else6.preheader ]
  %36 = trunc i64 %.0158 to i8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %9, i8 %36, i64 32, i1 false)
  %37 = load i8, ptr %9, align 1
  %38 = xor i8 %37, 81
  store i8 %38, ptr %9, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %9, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i63 = load i8, ptr %9, align 1
  %sunkaddr37 = getelementptr inbounds i8, ptr %9, i64 31
  %.val1.i64 = load i8, ptr %sunkaddr37, align 1
  %39 = xor i8 %.val1.i64, %.val.i63
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %9, i8 0, i64 32, i1 true)
  %.pn = zext i8 %39 to i64
  %.2 = add i64 %.19, %.pn
  %40 = add nuw nsw i64 %.0158, 1
  %exitcond.not = icmp eq i64 %1, %40
  br i1 %exitcond.not, label %common.ret, label %Else6
```

## owners.measure__func_48

```llvm
Block:
  %2 = alloca %Io.Timestamp, align 16
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca %Io.Timestamp, align 16
  %6 = alloca [32 x i8], align 1
  %7 = alloca [32 x i8], align 1
  %8 = getelementptr i8, ptr %.8.val, i64 704
  %.val23.val = load ptr, ptr %8, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %9 = getelementptr inbounds nuw i8, ptr %7, i64 32
  %10 = getelementptr inbounds nuw i8, ptr %6, i64 32
  %11 = icmp uge ptr %6, %9
  %12 = icmp uge ptr %7, %10
  %13 = or i1 %12, %11
  %.fr = freeze i1 %13
  br i1 %.fr, label %Else8.us.preheader, label %Else8

Else8.us.preheader:                               ; preds = %Block
  br label %Else8.us

Else8.us:                                         ; preds = %Else8.us.preheader, %Else8.us
  %.17.us = phi i64 [ %.2.us, %Else8.us ], [ 0, %Else8.us.preheader ]
  %.0156.us = phi i64 [ %19, %Else8.us ], [ 0, %Else8.us.preheader ]
  %14 = trunc i64 %.0156.us to i8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %7, i8 %14, i64 32, i1 false)
  %15 = load i8, ptr %7, align 1
  %16 = xor i8 %15, 81
  store i8 %16, ptr %7, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %6, ptr noundef nonnull align 1 dereferenceable(32) %7, i64 32, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %7, i8 0, i64 32, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %6, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i55.us = load i8, ptr %6, align 1
  %sunkaddr = getelementptr inbounds i8, ptr %6, i64 31
  %.val1.i56.us = load i8, ptr %sunkaddr, align 1
  %17 = xor i8 %.val1.i56.us, %.val.i55.us
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %6, i8 0, i64 32, i1 true)
  %18 = zext i8 %17 to i64
  %.2.us = add i64 %.17.us, %18
  %19 = add nuw nsw i64 %.0156.us, 1
  %exitcond.not = icmp eq i64 %1, %19
  br i1 %exitcond.not, label %common.ret, label %Else8.us

common.ret:                                       ; preds = %Else8.us
  %sunkaddr8 = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr8, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %20 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %21 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %22 = sub nsw i96 %20, %21
  call void asm sideeffect "", "r"(i64 %.2.us) #47
  %23 = sitofp i96 %22 to double
  %24 = uitofp nneg i64 %1 to double
  %25 = fdiv double %23, %24
  store double %25, ptr %0, align 8
  %.sroa.213.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.213.0..sroa_idx, align 8
  ret void

Else8:                                            ; preds = %Block
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(32) %7, i8 0, i64 32, i1 false)
  store i8 81, ptr %7, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable
```

## owners.measure__func_50

```llvm
Block:
  %2 = alloca %Io.Timestamp, align 16
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca ptr, align 8
  %7 = alloca %Io.Timestamp, align 16
  %8 = alloca [48 x i8], align 1
  %9 = alloca [48 x i8], align 1
  %10 = alloca %Material.Material, align 16
  %11 = getelementptr i8, ptr %.8.val, i64 704
  %.val23.val = load ptr, ptr %11, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %12 = icmp eq ptr @__anon_2657, @__anon_2661
  %13 = getelementptr inbounds nuw i8, ptr %9, i64 48
  %14 = getelementptr inbounds nuw i8, ptr %8, i64 48
  %15 = icmp uge ptr %8, %13
  %16 = icmp uge ptr %9, %14
  %17 = or i1 %16, %15
  %18 = getelementptr inbounds nuw i8, ptr %10, i64 16
  %19 = getelementptr inbounds nuw i8, ptr %10, i64 536
  br i1 %12, label %Else6.us.preheader, label %Block.split

Else6.us.preheader:                               ; preds = %Block
  br label %Else6.us

Else6.us:                                         ; preds = %Else6.us.preheader, %Else6.us
  %.19.us = phi i64 [ %.2.us, %Else6.us ], [ 0, %Else6.us.preheader ]
  %.0158.us = phi i64 [ %23, %Else6.us ], [ 0, %Else6.us.preheader ]
  %20 = trunc i64 %.0158.us to i8
  %sunkaddr = getelementptr inbounds i8, ptr %10, i64 1048
  store i8 0, ptr %sunkaddr, align 8
  store <2 x i64> <i64 256, i64 3>, ptr %10, align 16
  %sunkaddr33 = getelementptr inbounds i8, ptr %10, i64 16
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 16 dereferenceable(512) %18, i8 %20, i64 512, i1 false)
  %21 = xor i8 %20, 81
  %sunkaddr34 = getelementptr inbounds i8, ptr %10, i64 536
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(512) %19, i8 %21, i64 512, i1 false)
  %sunkaddr32 = getelementptr inbounds i8, ptr %10, i64 528
  store i64 0, ptr %sunkaddr32, align 16
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %10, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i.us = load i8, ptr %sunkaddr33, align 16
  %.val1.i.us = load i8, ptr %sunkaddr34, align 8
  %22 = xor i8 %.val1.i.us, %.val.i.us
  call void @llvm.memset.p0.i64(ptr nonnull align 16 %10, i8 0, i64 1056, i1 true)
  %.pn.us = zext i8 %22 to i64
  %.2.us = add i64 %.19.us, %.pn.us
  %23 = add nuw nsw i64 %.0158.us, 1
  %exitcond23.not = icmp eq i64 %1, %23
  br i1 %exitcond23.not, label %common.ret, label %Else6.us

Block.split:                                      ; preds = %Block
  %24 = icmp eq ptr @__anon_2657, @__anon_3162
  br i1 %24, label %Block.split.split.us, label %Else6.preheader

Else6.preheader:                                  ; preds = %Block.split
  br label %Else6

Block.split.split.us:                             ; preds = %Block.split
  %.fr = freeze i1 %17
  br i1 %.fr, label %Else6.us10.us.preheader, label %Else6.us10

Else6.us10.us.preheader:                          ; preds = %Block.split.split.us
  br label %Else6.us10.us

Else6.us10.us:                                    ; preds = %Else6.us10.us.preheader, %Else6.us10.us
  %.19.us11.us = phi i64 [ %.2.us16.us, %Else6.us10.us ], [ 0, %Else6.us10.us.preheader ]
  %.0158.us12.us = phi i64 [ %29, %Else6.us10.us ], [ 0, %Else6.us10.us.preheader ]
  %25 = trunc i64 %.0158.us12.us to i8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %9, i8 %25, i64 48, i1 false)
  %26 = load i8, ptr %9, align 1
  %27 = xor i8 %26, 81
  store i8 %27, ptr %9, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %9, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %8, ptr noundef nonnull align 1 dereferenceable(48) %9, i64 48, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %9, i8 0, i64 48, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %8, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i61.us.us = load i8, ptr %8, align 1
  %sunkaddr35 = getelementptr inbounds i8, ptr %8, i64 47
  %.val1.i62.us.us = load i8, ptr %sunkaddr35, align 1
  %28 = xor i8 %.val1.i62.us.us, %.val.i61.us.us
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %8, i8 0, i64 48, i1 true)
  %.pn.us15.us = zext i8 %28 to i64
  %.2.us16.us = add i64 %.19.us11.us, %.pn.us15.us
  %29 = add nuw nsw i64 %.0158.us12.us, 1
  %exitcond22.not = icmp eq i64 %1, %29
  br i1 %exitcond22.not, label %common.ret, label %Else6.us10.us

Else6.us10:                                       ; preds = %Block.split.split.us
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %9, i8 0, i64 48, i1 false)
  store i8 81, ptr %9, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %9, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable

common.ret:                                       ; preds = %Else6, %Else6.us10.us, %Else6.us
  %.us-phi = phi i64 [ %.2.us, %Else6.us ], [ %.2.us16.us, %Else6.us10.us ], [ %.2, %Else6 ]
  %sunkaddr36 = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr36, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %30 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %31 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %32 = sub nsw i96 %30, %31
  call void asm sideeffect "", "r"(i64 %.us-phi) #47
  %33 = sitofp i96 %32 to double
  %34 = uitofp nneg i64 %1 to double
  %35 = fdiv double %33, %34
  store double %35, ptr %0, align 8
  %.sroa.213.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.213.0..sroa_idx, align 8
  ret void

Else6:                                            ; preds = %Else6.preheader, %Else6
  %.19 = phi i64 [ %.2, %Else6 ], [ 0, %Else6.preheader ]
  %.0158 = phi i64 [ %40, %Else6 ], [ 0, %Else6.preheader ]
  %36 = trunc i64 %.0158 to i8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %9, i8 %36, i64 48, i1 false)
  %37 = load i8, ptr %9, align 1
  %38 = xor i8 %37, 81
  store i8 %38, ptr %9, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %9, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i63 = load i8, ptr %9, align 1
  %sunkaddr37 = getelementptr inbounds i8, ptr %9, i64 47
  %.val1.i64 = load i8, ptr %sunkaddr37, align 1
  %39 = xor i8 %.val1.i64, %.val.i63
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %9, i8 0, i64 48, i1 true)
  %.pn = zext i8 %39 to i64
  %.2 = add i64 %.19, %.pn
  %40 = add nuw nsw i64 %.0158, 1
  %exitcond.not = icmp eq i64 %1, %40
  br i1 %exitcond.not, label %common.ret, label %Else6
```

## owners.measure__func_56

```llvm
Block:
  %2 = alloca %Io.Timestamp, align 16
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca %Io.Timestamp, align 16
  %6 = alloca [48 x i8], align 1
  %7 = alloca [48 x i8], align 1
  %8 = getelementptr i8, ptr %.8.val, i64 704
  %.val23.val = load ptr, ptr %8, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %9 = getelementptr inbounds nuw i8, ptr %7, i64 48
  %10 = getelementptr inbounds nuw i8, ptr %6, i64 48
  %11 = icmp uge ptr %6, %9
  %12 = icmp uge ptr %7, %10
  %13 = or i1 %12, %11
  %.fr = freeze i1 %13
  br i1 %.fr, label %Else8.us.preheader, label %Else8

Else8.us.preheader:                               ; preds = %Block
  br label %Else8.us

Else8.us:                                         ; preds = %Else8.us.preheader, %Else8.us
  %.17.us = phi i64 [ %.2.us, %Else8.us ], [ 0, %Else8.us.preheader ]
  %.0156.us = phi i64 [ %19, %Else8.us ], [ 0, %Else8.us.preheader ]
  %14 = trunc i64 %.0156.us to i8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %7, i8 %14, i64 48, i1 false)
  %15 = load i8, ptr %7, align 1
  %16 = xor i8 %15, 81
  store i8 %16, ptr %7, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %6, ptr noundef nonnull align 1 dereferenceable(48) %7, i64 48, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %7, i8 0, i64 48, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %6, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i55.us = load i8, ptr %6, align 1
  %sunkaddr = getelementptr inbounds i8, ptr %6, i64 47
  %.val1.i56.us = load i8, ptr %sunkaddr, align 1
  %17 = xor i8 %.val1.i56.us, %.val.i55.us
  call void @llvm.memset.p0.i64(ptr nonnull align 1 %6, i8 0, i64 48, i1 true)
  %18 = zext i8 %17 to i64
  %.2.us = add i64 %.17.us, %18
  %19 = add nuw nsw i64 %.0156.us, 1
  %exitcond.not = icmp eq i64 %1, %19
  br i1 %exitcond.not, label %common.ret, label %Else8.us

common.ret:                                       ; preds = %Else8.us
  %sunkaddr8 = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr8, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %20 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %21 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %22 = sub nsw i96 %20, %21
  call void asm sideeffect "", "r"(i64 %.2.us) #47
  %23 = sitofp i96 %22 to double
  %24 = uitofp nneg i64 %1 to double
  %25 = fdiv double %23, %24
  store double %25, ptr %0, align 8
  %.sroa.213.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.213.0..sroa_idx, align 8
  ret void

Else8:                                            ; preds = %Block
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 1 dereferenceable(48) %7, i8 0, i64 48, i1 false)
  store i8 81, ptr %7, align 1
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable
```

## owners.measure__func_58

```llvm
Block:
  %2 = alloca %Io.Timestamp, align 16
  %3 = alloca ptr, align 8
  %4 = alloca %Io.Timestamp, align 16
  %5 = alloca %Material.Material, align 16
  %6 = getelementptr i8, ptr %.8.val, i64 704
  %.val23.val = load ptr, ptr %6, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %7 = getelementptr inbounds nuw i8, ptr %5, i64 16
  %8 = getelementptr inbounds nuw i8, ptr %5, i64 536
  br label %Block7

common.ret:                                       ; preds = %Block7
  %sunkaddr = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %9 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %10 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %11 = sub nsw i96 %9, %10
  call void asm sideeffect "", "r"(i64 %.2) #47
  %12 = sitofp i96 %11 to double
  %13 = uitofp nneg i64 %1 to double
  %14 = fdiv double %12, %13
  store double %14, ptr %0, align 8
  %.sroa.213.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.213.0..sroa_idx, align 8
  ret void

Block7:                                           ; preds = %Block, %Block7
  %.16 = phi i64 [ 0, %Block ], [ %.2, %Block7 ]
  %.0155 = phi i64 [ 0, %Block ], [ %19, %Block7 ]
  %15 = trunc i64 %.0155 to i8
  %sunkaddr7 = getelementptr inbounds i8, ptr %5, i64 1048
  store i8 0, ptr %sunkaddr7, align 8
  store <2 x i64> <i64 256, i64 3>, ptr %5, align 16
  %sunkaddr9 = getelementptr inbounds i8, ptr %5, i64 16
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 16 dereferenceable(512) %7, i8 %15, i64 512, i1 false)
  %16 = xor i8 %15, 81
  %sunkaddr10 = getelementptr inbounds i8, ptr %5, i64 536
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(512) %8, i8 %16, i64 512, i1 false)
  %sunkaddr8 = getelementptr inbounds i8, ptr %5, i64 528
  store i64 0, ptr %sunkaddr8, align 16
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %5, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.val.i = load i8, ptr %sunkaddr9, align 16
  %.val1.i = load i8, ptr %sunkaddr10, align 8
  %17 = xor i8 %.val1.i, %.val.i
  call void @llvm.memset.p0.i64(ptr nonnull align 16 %5, i8 0, i64 1056, i1 true)
  %18 = zext i8 %17 to i64
  %.2 = add i64 %.16, %18
  %19 = add nuw nsw i64 %.0155, 1
  %exitcond.not = icmp eq i64 %1, %19
  br i1 %exitcond.not, label %common.ret, label %Block7
```

## owners.measure__func_60

```llvm
Block:
  %2 = alloca %Io.Timestamp, align 16
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca %Io.Timestamp, align 16
  %6 = alloca %Material.Material, align 8
  %7 = alloca %Material.Material, align 16
  %8 = getelementptr i8, ptr %.8.val, i64 704
  %.val23.val = load ptr, ptr %8, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %9 = getelementptr inbounds nuw i8, ptr %7, i64 16
  %10 = getelementptr inbounds nuw i8, ptr %7, i64 536
  %11 = getelementptr inbounds nuw i8, ptr %7, i64 1056
  %12 = getelementptr inbounds nuw i8, ptr %6, i64 1056
  %13 = icmp uge ptr %6, %11
  %14 = icmp uge ptr %7, %12
  %15 = or i1 %14, %13
  %.fr = freeze i1 %15
  br i1 %.fr, label %Else9.us.preheader, label %Else9

Else9.us.preheader:                               ; preds = %Block
  br label %Else9.us

Else9.us:                                         ; preds = %Else9.us.preheader, %Else9.us
  %.17.us = phi i64 [ %.2.us, %Else9.us ], [ 0, %Else9.us.preheader ]
  %.0156.us = phi i64 [ %20, %Else9.us ], [ 0, %Else9.us.preheader ]
  %16 = trunc i64 %.0156.us to i8
  %sunkaddr = getelementptr inbounds i8, ptr %7, i64 1048
  store i8 0, ptr %sunkaddr, align 8
  store <2 x i64> <i64 256, i64 3>, ptr %7, align 16
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 16 dereferenceable(512) %9, i8 %16, i64 512, i1 false)
  %17 = xor i8 %16, 81
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(512) %10, i8 %17, i64 512, i1 false)
  %sunkaddr8 = getelementptr inbounds i8, ptr %7, i64 528
  store i64 0, ptr %sunkaddr8, align 16
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call void @llvm.memcpy.p0.p0.i64(ptr noundef nonnull align 8 dereferenceable(1056) %6, ptr noundef nonnull align 16 dereferenceable(1056) %7, i64 1056, i1 false)
  call void @llvm.memset.p0.i64(ptr nonnull align 16 %7, i8 0, i64 1056, i1 true)
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %6, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %sunkaddr9 = getelementptr inbounds i8, ptr %6, i64 16
  %.val.i52.us = load i8, ptr %sunkaddr9, align 8
  %sunkaddr10 = getelementptr inbounds i8, ptr %6, i64 536
  %.val1.i53.us = load i8, ptr %sunkaddr10, align 8
  %18 = xor i8 %.val1.i53.us, %.val.i52.us
  call void @llvm.memset.p0.i64(ptr nonnull align 8 %6, i8 0, i64 1056, i1 true)
  %19 = zext i8 %18 to i64
  %.2.us = add i64 %.17.us, %19
  %20 = add nuw nsw i64 %.0156.us, 1
  %exitcond.not = icmp eq i64 %1, %20
  br i1 %exitcond.not, label %common.ret, label %Else9.us

common.ret:                                       ; preds = %Else9.us
  %sunkaddr11 = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr11, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %21 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %22 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %23 = sub nsw i96 %21, %22
  call void asm sideeffect "", "r"(i64 %.2.us) #47
  %24 = sitofp i96 %23 to double
  %25 = uitofp nneg i64 %1 to double
  %26 = fdiv double %24, %25
  store double %26, ptr %0, align 8
  %.sroa.213.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.213.0..sroa_idx, align 8
  ret void

Else9:                                            ; preds = %Block
  %27 = getelementptr inbounds nuw i8, ptr %7, i64 8
  %sunkaddr12 = getelementptr inbounds i8, ptr %7, i64 1048
  store i8 0, ptr %sunkaddr12, align 8
  store i64 256, ptr %7, align 16
  store i64 3, ptr %27, align 8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 16 dereferenceable(512) %9, i8 0, i64 512, i1 false)
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(512) %10, i8 81, i64 512, i1 false)
  %sunkaddr13 = getelementptr inbounds i8, ptr %7, i64 528
  store i64 0, ptr %sunkaddr13, align 16
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).memcpyAlias"()
  unreachable
```

## owners.measure__func_62

```llvm
Block:
  %2 = alloca %Io.Timestamp, align 16
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca ptr, align 8
  %6 = alloca %Io.Timestamp, align 16
  %7 = alloca %"cases.Direct(cases.Counts)", align 8
  %8 = getelementptr i8, ptr %.8.val, i64 704
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(17) %7, i8 0, i64 17, i1 false)
  %.val23.val = load ptr, ptr %8, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  br label %Then5

common.ret:                                       ; preds = %Block7
  %sunkaddr = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %9 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %10 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %11 = sub nsw i96 %9, %10
  call void asm sideeffect "", "r"(i64 %.2) #47
  %12 = sitofp i96 %11 to double
  %13 = uitofp nneg i64 %1 to double
  %14 = fdiv double %12, %13
  store double %14, ptr %0, align 8
  %.sroa.213.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.213.0..sroa_idx, align 8
  ret void

Block7:                                           ; preds = %cases.uncharge.exit.i, %Else.i.i, %cases.lock__func_808.exit.i
  %common.ret.op.i14.i = phi i64 [ 1, %cases.uncharge.exit.i ], [ 0, %Else.i.i ], [ 0, %cases.lock__func_808.exit.i ]
  %sunkaddr13 = getelementptr inbounds i8, ptr %7, i64 16
  store atomic i8 0, ptr %sunkaddr13 release, align 8
  %.2 = add i64 %common.ret.op.i14.i, %.17
  %15 = add nuw nsw i64 %.0156, 1
  %exitcond.not = icmp eq i64 %15, %1
  br i1 %exitcond.not, label %common.ret, label %Then5

Then5:                                            ; preds = %Block, %Block7
  %.17 = phi i64 [ 0, %Block ], [ %.2, %Block7 ]
  %.0156 = phi i64 [ 0, %Block ], [ %15, %Block7 ]
  %sunkaddr14 = getelementptr inbounds i8, ptr %7, i64 16
  %16 = cmpxchg weak ptr %sunkaddr14, i8 0, i8 1 acquire monotonic, align 1
  %17 = extractvalue { i8, i1 } %16, 1
  br i1 %17, label %cases.lock__func_808.exit.i, label %Then.i.i.preheader

Then.i.i.preheader:                               ; preds = %Then5
  br label %Then.i.i

Then.i.i:                                         ; preds = %Then.i.i.preheader, %Then.i.i
  call void asm sideeffect "isb", ""() #47
  %sunkaddr15 = getelementptr inbounds i8, ptr %7, i64 16
  %18 = cmpxchg weak ptr %sunkaddr15, i8 0, i8 1 acquire monotonic, align 1
  %19 = extractvalue { i8, i1 } %18, 1
  br i1 %19, label %cases.lock__func_808.exit.i, label %Then.i.i

cases.lock__func_808.exit.i:                      ; preds = %Then.i.i, %Then5
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %20 = load i64, ptr %7, align 8
  %21 = icmp ugt i64 %20, 63
  br i1 %21, label %Block7, label %Else.i.i

Else.i.i:                                         ; preds = %cases.lock__func_808.exit.i
  %sunkaddr16 = getelementptr inbounds i8, ptr %7, i64 8
  %22 = load i64, ptr %sunkaddr16, align 8
  %23 = icmp ugt i64 %22, 16777088
  br i1 %23, label %Block7, label %Else.i

Else.i:                                           ; preds = %Else.i.i
  %24 = add nuw nsw i64 %20, 1
  store i64 %24, ptr %7, align 8
  %25 = add nuw nsw i64 %22, 128
  %sunkaddr17 = getelementptr inbounds i8, ptr %7, i64 8
  store i64 %25, ptr %sunkaddr17, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %sunkaddr18 = getelementptr inbounds i8, ptr %7, i64 16
  store atomic i8 0, ptr %sunkaddr18 release, align 8
  %26 = cmpxchg weak ptr %sunkaddr18, i8 0, i8 1 acquire monotonic, align 1
  %27 = extractvalue { i8, i1 } %26, 1
  br i1 %27, label %cases.lock__func_808.exit10.i, label %Then.i8.i.preheader

Then.i8.i.preheader:                              ; preds = %Else.i
  br label %Then.i8.i

Then.i8.i:                                        ; preds = %Then.i8.i.preheader, %Then.i8.i
  call void asm sideeffect "isb", ""() #47
  %sunkaddr19 = getelementptr inbounds i8, ptr %7, i64 16
  %28 = cmpxchg weak ptr %sunkaddr19, i8 0, i8 1 acquire monotonic, align 1
  %29 = extractvalue { i8, i1 } %28, 1
  br i1 %29, label %cases.lock__func_808.exit10.i, label %Then.i8.i

cases.lock__func_808.exit10.i:                    ; preds = %Then.i8.i, %Else.i
  %sunkaddr20 = getelementptr inbounds i8, ptr %7, i64 8
  %30 = load i64, ptr %sunkaddr20, align 8
  %31 = icmp ult i64 %30, 128
  br i1 %31, label %Then1.i.i, label %Else.i11.i

Else.i11.i:                                       ; preds = %cases.lock__func_808.exit10.i
  %32 = load i64, ptr %7, align 8
  %33 = icmp eq i64 %32, 0
  br i1 %33, label %Then1.i.i, label %cases.uncharge.exit.i

Then1.i.i:                                        ; preds = %Else.i11.i, %cases.lock__func_808.exit10.i
  call fastcc void @debug.defaultPanic(ptr nonnull readonly align 1 @__anon_26610, i64 36, i64 undef, i8 0)
  unreachable

cases.uncharge.exit.i:                            ; preds = %Else.i11.i
  %34 = add i64 %32, -1
  store i64 %34, ptr %7, align 8
  %35 = add i64 %30, -128
  %sunkaddr21 = getelementptr inbounds i8, ptr %7, i64 8
  store i64 %35, ptr %sunkaddr21, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %7, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  br label %Block7
```

## owners.measure__func_64

```llvm
Block:
  %2 = alloca %Io.Timestamp, align 16
  %3 = alloca ptr, align 8
  %4 = alloca ptr, align 8
  %5 = alloca %Io.Timestamp, align 16
  %6 = alloca %"cases.Direct(cases.Completion)", align 8
  %7 = getelementptr i8, ptr %.8.val, i64 704
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(25) %6, i8 0, i64 25, i1 false)
  %.val23.val = load ptr, ptr %7, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  br label %Then6

common.ret:                                       ; preds = %Block7
  %sunkaddr = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %8 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %9 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %10 = sub nsw i96 %8, %9
  call void asm sideeffect "", "r"(i64 %.2) #47
  %11 = sitofp i96 %10 to double
  %12 = uitofp nneg i64 %1 to double
  %13 = fdiv double %11, %12
  store double %13, ptr %0, align 8
  %.sroa.213.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 0, ptr %.sroa.213.0..sroa_idx, align 8
  ret void

Block7:                                           ; preds = %cases.lock__func_807.exit15.i
  %.sroa.010.0.copyload.i = load i64, ptr %6, align 8
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %6, i8 0, i64 16, i1 false)
  %sunkaddr9 = getelementptr inbounds i8, ptr %6, i64 16
  store i8 2, ptr %sunkaddr9, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %6, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %sunkaddr10 = getelementptr inbounds i8, ptr %6, i64 24
  store atomic i8 0, ptr %sunkaddr10 release, align 8
  %.2 = add i64 %.sroa.010.0.copyload.i, %.17
  %14 = add nuw nsw i64 %.0156, 1
  %exitcond.not = icmp eq i64 %14, %1
  br i1 %exitcond.not, label %common.ret, label %Then6

Then6:                                            ; preds = %Block, %Block7
  %.17 = phi i64 [ 0, %Block ], [ %.2, %Block7 ]
  %.0156 = phi i64 [ 0, %Block ], [ %14, %Block7 ]
  %sunkaddr11 = getelementptr inbounds i8, ptr %6, i64 24
  %15 = cmpxchg weak ptr %sunkaddr11, i8 0, i8 1 acquire monotonic, align 1
  %16 = extractvalue { i8, i1 } %15, 1
  br i1 %16, label %cases.lock__func_807.exit.i, label %Then.i.i46.preheader

Then.i.i46.preheader:                             ; preds = %Then6
  br label %Then.i.i46

Then.i.i46:                                       ; preds = %Then.i.i46.preheader, %Then.i.i46
  call void asm sideeffect "isb", ""() #47
  %sunkaddr12 = getelementptr inbounds i8, ptr %6, i64 24
  %17 = cmpxchg weak ptr %sunkaddr12, i8 0, i8 1 acquire monotonic, align 1
  %18 = extractvalue { i8, i1 } %17, 1
  br i1 %18, label %cases.lock__func_807.exit.i, label %Then.i.i46

cases.lock__func_807.exit.i:                      ; preds = %Then.i.i46, %Then6
  store i64 %.0156, ptr %6, align 8
  %sunkaddr13 = getelementptr inbounds i8, ptr %6, i64 8
  store i8 1, ptr %sunkaddr13, align 8
  %sunkaddr14 = getelementptr inbounds i8, ptr %6, i64 16
  store i8 1, ptr %sunkaddr14, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %6, ptr %2, align 8
  call void asm sideeffect "", "m,~{memory}"(ptr nonnull %2) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %sunkaddr15 = getelementptr inbounds i8, ptr %6, i64 24
  store atomic i8 0, ptr %sunkaddr15 release, align 8
  %19 = cmpxchg weak ptr %sunkaddr15, i8 0, i8 1 acquire monotonic, align 1
  %20 = extractvalue { i8, i1 } %19, 1
  br i1 %20, label %cases.lock__func_807.exit15.i, label %Then.i14.i.preheader

Then.i14.i.preheader:                             ; preds = %cases.lock__func_807.exit.i
  br label %Then.i14.i

Then.i14.i:                                       ; preds = %Then.i14.i.preheader, %Then.i14.i
  call void asm sideeffect "isb", ""() #47
  %sunkaddr16 = getelementptr inbounds i8, ptr %6, i64 24
  %21 = cmpxchg weak ptr %sunkaddr16, i8 0, i8 1 acquire monotonic, align 1
  %22 = extractvalue { i8, i1 } %21, 1
  br i1 %22, label %cases.lock__func_807.exit15.i, label %Then.i14.i

cases.lock__func_807.exit15.i:                    ; preds = %Then.i14.i, %cases.lock__func_807.exit.i
  %sunkaddr17 = getelementptr inbounds i8, ptr %6, i64 8
  %.sroa.211.0.copyload.i = load i8, ptr %sunkaddr17, align 8
  %23 = trunc nuw i8 %.sroa.211.0.copyload.i to i1
  br i1 %23, label %Block7, label %Else.i47

Else.i47:                                         ; preds = %cases.lock__func_807.exit15.i
  call fastcc void @"debug.FullPanic((function 'defaultPanic')).unwrapNull"()
  unreachable
```

## owners.measure__func_66

```llvm
Then2:
  %2 = alloca { ptr, i64 }, align 8
  %3 = alloca %Io.Timestamp, align 16
  %4 = alloca %Io.Timestamp, align 16
  %5 = alloca %Io.Group, align 8
  %6 = alloca %"cases.Direct(usize)", align 8
  store i64 0, ptr %6, align 8
  %7 = getelementptr inbounds nuw i8, ptr %6, i64 8
  store i8 0, ptr %7, align 8
  %8 = getelementptr i8, ptr %.8.val, i64 704
  %.val23.val = load ptr, ptr %8, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %5, i8 0, i64 16, i1 false)
  %9 = getelementptr i8, ptr %.8.val, i64 48
  %.sroa.2.0..sroa_idx = getelementptr inbounds nuw i8, ptr %2, i64 8
  %.val27.val = load ptr, ptr %9, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %6, ptr %2, align 8
  store i64 %1, ptr %.sroa.2.0..sroa_idx, align 8
  %10 = call fastcc i16 %.val27.val(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull readonly align 1 %2, i64 16, i6 3, ptr nonnull readonly align 4 @Io.Group.concurrent__func_24.TypeErased.start) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.not20 = icmp eq i16 %10, 0
  br i1 %.not20, label %Loop, label %TryRet

common.ret:                                       ; preds = %Then.i37, %TryRet1, %Then.i32, %TryRet, %Block2
  %.sink = phi i16 [ %.lcssa, %Then.i32 ], [ 0, %Block2 ], [ %.lcssa, %TryRet ], [ %21, %TryRet1 ], [ %21, %Then.i37 ]
  %.sroa.18.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 %.sink, ptr %.sroa.18.0..sroa_idx, align 8
  ret void

Block2:                                           ; preds = %Then.i43, %TryCont1
  %sunkaddr = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %11 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %12 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %13 = sub nsw i96 %11, %12
  call void asm sideeffect "", "r"(i64 %28) #47
  %14 = sitofp i96 %13 to double
  %15 = uitofp nneg i64 %28 to double
  %16 = fdiv double %14, %15
  store double %16, ptr %0, align 8
  br label %common.ret

Loop:                                             ; preds = %Then2
  %sunkaddr16 = getelementptr i8, ptr %.8.val, i64 48
  %.val27.val.1 = load ptr, ptr %sunkaddr16, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %6, ptr %2, align 8
  %sunkaddr17 = getelementptr inbounds i8, ptr %2, i64 8
  store i64 %1, ptr %sunkaddr17, align 8
  %17 = call fastcc i16 %.val27.val.1(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull readonly align 1 %2, i64 16, i6 3, ptr nonnull readonly align 4 @Io.Group.concurrent__func_24.TypeErased.start) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.not20.1 = icmp eq i16 %17, 0
  br i1 %.not20.1, label %Loop.1, label %TryRet

Loop.1:                                           ; preds = %Loop
  %18 = load atomic ptr, ptr %5 acquire, align 8
  %.not.i = icmp eq ptr %18, null
  br i1 %.not.i, label %TryCont1, label %Io.Group.await.exit

Io.Group.await.exit:                              ; preds = %Loop.1
  %19 = getelementptr inbounds nuw i8, ptr %.8.val, i64 56
  %20 = load ptr, ptr %19, align 8
  %21 = call fastcc i16 %20(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull align 1 %18) #47
  %.not = icmp eq i16 %21, 0
  br i1 %.not, label %TryCont1, label %TryRet1

TryRet:                                           ; preds = %Loop, %Then2
  %.lcssa = phi i16 [ %10, %Then2 ], [ %17, %Loop ]
  %22 = load atomic ptr, ptr %5 acquire, align 8
  %.not.i31 = icmp eq ptr %22, null
  br i1 %.not.i31, label %common.ret, label %Then.i32

Then.i32:                                         ; preds = %TryRet
  %23 = getelementptr inbounds nuw i8, ptr %.8.val, i64 64
  %24 = load ptr, ptr %23, align 8
  call fastcc void %24(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull align 1 %22) #47
  br label %common.ret

TryRet1:                                          ; preds = %Io.Group.await.exit
  %25 = load atomic ptr, ptr %5 acquire, align 8
  %.not.i36 = icmp eq ptr %25, null
  br i1 %.not.i36, label %common.ret, label %Then.i37

Then.i37:                                         ; preds = %TryRet1
  %26 = getelementptr inbounds nuw i8, ptr %.8.val, i64 64
  %27 = load ptr, ptr %26, align 8
  call fastcc void %27(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull align 1 %25) #47
  br label %common.ret

TryCont1:                                         ; preds = %Loop.1, %Io.Group.await.exit
  %28 = load i64, ptr %6, align 8
  %29 = load atomic ptr, ptr %5 acquire, align 8
  %.not.i42 = icmp eq ptr %29, null
  br i1 %.not.i42, label %Block2, label %Then.i43

Then.i43:                                         ; preds = %TryCont1
  %30 = getelementptr inbounds nuw i8, ptr %.8.val, i64 64
  %31 = load ptr, ptr %30, align 8
  call fastcc void %31(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull align 1 %29) #47
  br label %Block2
```

## owners.measure__func_68

```llvm
Entry:
  %2 = alloca { ptr, i64 }, align 8
  %3 = alloca %Io.Timestamp, align 16
  %4 = alloca %Io.Timestamp, align 16
  %5 = alloca %Io.Group, align 8
  %6 = alloca %"cases.Direct(usize)", align 8
  store i64 0, ptr %6, align 8
  %7 = getelementptr inbounds nuw i8, ptr %6, i64 8
  store i8 0, ptr %7, align 8
  %8 = icmp eq ptr @__anon_2675, @__anon_2672
  %spec.select = select i1 %8, i64 2, i64 8
  %9 = getelementptr i8, ptr %.8.val, i64 704
  %.val23.val = load ptr, ptr %9, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val23.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.01.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  call void @llvm.memset.p0.i64(ptr noundef nonnull align 8 dereferenceable(16) %5, i8 0, i64 16, i1 false)
  br label %Then3

common.ret:                                       ; preds = %Then.i38, %TryRet1, %Then.i33, %TryRet, %Block2
  %.sink = phi i16 [ %16, %Then.i33 ], [ 0, %Block2 ], [ %16, %TryRet ], [ %20, %TryRet1 ], [ %20, %Then.i38 ]
  %.sroa.18.0..sroa_idx = getelementptr inbounds nuw i8, ptr %0, i64 8
  store i16 %.sink, ptr %.sroa.18.0..sroa_idx, align 8
  ret void

Block2:                                           ; preds = %Then.i44, %TryCont1
  %sunkaddr = getelementptr i8, ptr %.8.val, i64 704
  %.val21.val = load ptr, ptr %sunkaddr, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  call fastcc void %.val21.val(ptr dead_on_unwind nonnull writeonly sret(%Io.Timestamp) align 16 captures(none) %2, ptr align 1 %.0.val, i3 1) #47
  %.sroa.0.0.copyload = load i128, ptr %2, align 16
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %10 = trunc nsw i128 %.sroa.0.0.copyload to i96
  %11 = trunc nsw i128 %.sroa.01.sroa.0.0.copyload to i96
  %12 = sub nsw i96 %10, %11
  call void asm sideeffect "", "r"(i64 %27) #47
  %13 = sitofp i96 %12 to double
  %14 = uitofp nneg i64 %27 to double
  %15 = fdiv double %13, %14
  store double %15, ptr %0, align 8
  br label %common.ret

Loop:                                             ; preds = %Then3
  %lsr.iv.next = add i64 %lsr.iv, -1
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %Else3, label %Then3

Then3:                                            ; preds = %Entry, %Loop
  %lsr.iv = phi i64 [ %spec.select, %Entry ], [ %lsr.iv.next, %Loop ]
  %sunkaddr21 = getelementptr i8, ptr %.8.val, i64 48
  %.val27.val = load ptr, ptr %sunkaddr21, align 8
  call void @llvm.lifetime.start.p0(ptr nonnull %2)
  store ptr %6, ptr %2, align 8
  %sunkaddr22 = getelementptr inbounds i8, ptr %2, i64 8
  store i64 %1, ptr %sunkaddr22, align 8
  %16 = call fastcc i16 %.val27.val(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull readonly align 1 %2, i64 16, i6 3, ptr nonnull readonly align 4 @Io.Group.concurrent__func_24.TypeErased.start) #47
  call void @llvm.lifetime.end.p0(ptr nonnull %2)
  %.not20 = icmp eq i16 %16, 0
  br i1 %.not20, label %Loop, label %TryRet

Else3:                                            ; preds = %Loop
  %17 = load atomic ptr, ptr %5 acquire, align 8
  %.not.i = icmp eq ptr %17, null
  br i1 %.not.i, label %TryCont1, label %Io.Group.await.exit

Io.Group.await.exit:                              ; preds = %Else3
  %18 = getelementptr inbounds nuw i8, ptr %.8.val, i64 56
  %19 = load ptr, ptr %18, align 8
  %20 = call fastcc i16 %19(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull align 1 %17) #47
  %.not = icmp eq i16 %20, 0
  br i1 %.not, label %TryCont1, label %TryRet1

TryRet:                                           ; preds = %Then3
  %21 = load atomic ptr, ptr %5 acquire, align 8
  %.not.i32 = icmp eq ptr %21, null
  br i1 %.not.i32, label %common.ret, label %Then.i33

Then.i33:                                         ; preds = %TryRet
  %22 = getelementptr inbounds nuw i8, ptr %.8.val, i64 64
  %23 = load ptr, ptr %22, align 8
  call fastcc void %23(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull align 1 %21) #47
  br label %common.ret

TryRet1:                                          ; preds = %Io.Group.await.exit
  %24 = load atomic ptr, ptr %5 acquire, align 8
  %.not.i37 = icmp eq ptr %24, null
  br i1 %.not.i37, label %common.ret, label %Then.i38

Then.i38:                                         ; preds = %TryRet1
  %25 = getelementptr inbounds nuw i8, ptr %.8.val, i64 64
  %26 = load ptr, ptr %25, align 8
  call fastcc void %26(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull align 1 %24) #47
  br label %common.ret

TryCont1:                                         ; preds = %Else3, %Io.Group.await.exit
  %27 = load i64, ptr %6, align 8
  %28 = load atomic ptr, ptr %5 acquire, align 8
  %.not.i43 = icmp eq ptr %28, null
  br i1 %.not.i43, label %Block2, label %Then.i44

Then.i44:                                         ; preds = %TryCont1
  %29 = getelementptr inbounds nuw i8, ptr %.8.val, i64 64
  %30 = load ptr, ptr %29, align 8
  call fastcc void %30(ptr align 1 %.0.val, ptr nonnull align 8 %5, ptr nonnull align 1 %28) #47
  br label %Block2
```
