/* Copyright (C) 2003-2014 Free Software Foundation, Inc.
   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, see
   <http://www.gnu.org/licenses/>.  */

#include <sysdep.h>
#include <shlib-compat.h>
#include <lowlevellock.h>
#include <lowlevelcond.h>
#include <tcb-offsets.h>
#include <kernel-features.h>
#include "lowlevel-atomic.h"

	.text

/* int pthread_cond_wait (pthread_cond_t *cond, pthread_mutex_t *mutex)  */
	.globl	__pthread_cond_wait
	.type	__pthread_cond_wait, @function
	.align	5
	cfi_startproc
__pthread_cond_wait:
.LSTARTCODE:
#ifdef SHARED
	cfi_personality(DW_EH_PE_pcrel | DW_EH_PE_sdata4 | DW_EH_PE_indirect,
			DW.ref.__gcc_personality_v0)
	cfi_lsda(DW_EH_PE_pcrel | DW_EH_PE_sdata4, .LexceptSTART)
#else
	cfi_personality(DW_EH_PE_absptr, __gcc_personality_v0)
	cfi_lsda(DW_EH_PE_absptr, .LexceptSTART)
#endif
	mov.l	r8, @-r15
	cfi_adjust_cfa_offset (4)
	cfi_rel_offset (r8, 0)
	mov.l	r9, @-r15
	cfi_adjust_cfa_offset (4)
	cfi_rel_offset (r9, 0)
	mov.l	r10, @-r15
	cfi_adjust_cfa_offset (4)
	cfi_rel_offset (r10, 0)
	mov.l	r11, @-r15
	cfi_adjust_cfa_offset (4)
	cfi_rel_offset (r11, 0)
	mov.l	r12, @-r15
	cfi_adjust_cfa_offset (4)
	cfi_rel_offset (r12, 0)
	sts.l	pr, @-r15
	cfi_adjust_cfa_offset (4)
	cfi_rel_offset (pr, 0)
	add	#-48, r15
	cfi_adjust_cfa_offset (48)

	mov	r4, r8
	mov	r5, r9
#ifdef PIC
	mova	.Lgot0, r0
	mov.l	.Lgot0, r12
	add	r0, r12
#endif

	/* Get internal lock.  */
	mov	#0, r3
	mov	#1, r4
#if cond_lock != 0
	CMPXCHG (r3, @(cond_lock,r8), r4, r2)
#else
	CMPXCHG (r3, @r8, r4, r2)
#endif
	bt	2f
	bra	1f
	 nop
#ifdef PIC
	.align	2
.Lgot0:
	.long	_GLOBAL_OFFSET_TABLE_
#endif

2:
	/* Store the reference to the mutex.  If there is already a
	   different value in there this is a bad user bug.  */
	mov.l	@(dep_mutex,r8),r0
	cmp/eq	#-1, r0
	bt	15f
	mov.l	r9, @(dep_mutex,r8)

15:
	/* Unlock the mutex.  */
	mov.l	.Lmunlock0, r1
	mov	#0, r5
	bsrf	r1
	 mov	r9, r4
.Lmunlock0b:

	tst	r0, r0
	bt	0f
	bra	12f
	 nop
0:
	mov	#1, r2
	mov	#0, r3

	clrt
	mov.l	@(total_seq,r8),r0
	mov.l	@(total_seq+4,r8),r1
	addc	r2, r0
	addc	r3, r1
	mov.l	r0,@(total_seq,r8)
	mov.l	r1,@(total_seq+4,r8)
	mov.l	@(cond_futex,r8),r0
	add	r2, r0
	mov.l	r0,@(cond_futex,r8)
	mov	#(1 << nwaiters_shift), r2
	mov.l	@(cond_nwaiters,r8), r0
	add	r2, r0
	mov.l	r0, @(cond_nwaiters,r8)

	/* Get and store current wakeup_seq value.  */
	mov.l	@(wakeup_seq,r8), r10
	mov.l	@(wakeup_seq+4,r8), r11
	mov.l	@(broadcast_seq,r8), r0
	mov.l	r0, @(4,r15)

8:
	mov.l	@(cond_futex,r8),r0
	mov.l	r0, @(8,r15)

	/* Unlock.  */
#if cond_lock != 0
	DEC (@(cond_lock,r8), r2)
#else
	DEC (@r8, r2)
#endif
	tst	r2, r2
	bf	3f
4:
.LcleanupSTART:
	mov.l	.Lenable0, r1
	bsrf	r1
	 nop
.Lenable0b:
	mov.l	r0, @r15

	mov	#0, r7
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bt/s	99f
	 mov	#FUTEX_WAIT, r5
#ifdef __ASSUME_PRIVATE_FUTEX
	mov	#(FUTEX_WAIT|FUTEX_PRIVATE_FLAG), r5
	extu.b	r5, r5
#else
	stc	gbr, r1
	mov.w	.Lpfoff0, r2
	add	r2, r1
	mov.l	@r1, r5
	mov	#FUTEX_WAIT, r0
	or	r0, r5
#endif
99:
	mov.l	@(8,r15), r6
	mov	r8, r4
	add	#cond_futex, r4
	mov	#SYS_futex, r3
	extu.b	r3, r3
	trapa	#0x14
	SYSCALL_INST_PAD

	mov.l	.Ldisable0, r1
	bsrf	r1
	 mov.l	@r15, r4
.Ldisable0b:
.LcleanupEND:

	/* Lock.  */
	mov	#0, r3
	mov	#1, r4
#if cond_lock != 0
	CMPXCHG (r3, @(cond_lock,r8), r4, r2)
#else
	CMPXCHG (r3, @r8, r4, r2)
#endif
	bf	5f
6:
	mov.l	@(broadcast_seq,r8), r0
	mov.l	@(4,r15), r1
	cmp/eq	r0, r1
	bf	16f

	mov.l	@(woken_seq,r8), r0
	mov.l	@(woken_seq+4,r8), r1

	mov.l	@(wakeup_seq,r8), r2
	mov.l	@(wakeup_seq+4,r8), r3

	cmp/eq	r3, r11
	bf	7f
	cmp/eq	r2, r10
	bt	8b
7:
	cmp/eq	r1, r3
	bf	9f
	cmp/eq	r0, r2
	bt	8b
9:
	mov	#1, r2
	mov	#0, r3

	clrt
	mov.l	@(woken_seq,r8),r0
	mov.l	@(woken_seq+4,r8),r1
	addc	r2, r0
	addc	r3, r1
	mov.l	r0,@(woken_seq,r8)
	mov.l	r1,@(woken_seq+4,r8)

16:
	mov	#(1 << nwaiters_shift), r2
	mov.l	@(cond_nwaiters,r8),r0
	sub	r2, r0
	mov.l	r0,@(cond_nwaiters,r8)

	/* Wake up a thread which wants to destroy the condvar object.  */
	mov.l	@(total_seq,r8),r0
	mov.l	@(total_seq+4,r8),r1
	and	r1, r0
	not	r0, r0
	cmp/eq	#0, r0
	bf/s	17f
	 mov	#((1 << nwaiters_shift) - 1), r1
	not	r1, r1
	mov.l	@(cond_nwaiters,r8),r0
	tst	r1, r0
	bf	17f

	mov	r8, r4
	add	#cond_nwaiters, r4
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bt/s	99f
	 mov	#FUTEX_WAKE, r5
#ifdef __ASSUME_PRIVATE_FUTEX
	mov	#(FUTEX_WAKE|FUTEX_PRIVATE_FLAG), r5
	extu.b	r5, r5
#else
	stc	gbr, r1
	mov.w	.Lpfoff0, r2
	add	r2, r1
	mov.l	@r1, r5
	mov	#FUTEX_WAKE, r0
	or	r0, r5
#endif
99:
	mov	#1, r6
	mov	#0, r7
	mov	#SYS_futex, r3
	extu.b	r3, r3
	trapa	#0x14
	SYSCALL_INST_PAD

17:
#if cond_lock != 0
	DEC (@(cond_lock,r8), r2)
#else
	DEC (@r8, r2)
#endif
	tst	r2, r2
	bf	10f

11:
	mov.l	.Lmlocki0, r1
	bsrf	r1
	 mov	r9, r4
.Lmlocki0b:
	/* We return the result of the mutex_lock operation.  */

14:
	cfi_remember_state
	add	#48, r15
	cfi_adjust_cfa_offset (-48)
	lds.l	@r15+, pr
	cfi_adjust_cfa_offset (-4)
	cfi_restore (pr)
	mov.l	@r15+, r12
	cfi_adjust_cfa_offset (-4)
	cfi_restore (r12)
	mov.l	@r15+, r11
	cfi_adjust_cfa_offset (-4)
	cfi_restore (r11)
	mov.l	@r15+, r10
	cfi_adjust_cfa_offset (-4)
	cfi_restore (r10)
	mov.l	@r15+, r9
	cfi_adjust_cfa_offset (-4)
	cfi_restore (r9)
	rts
	 mov.l	@r15+, r8
	/* Omit CFI for restore in delay slot.  */
	cfi_restore_state

#ifndef __ASSUME_PRIVATE_FUTEX
.Lpfoff0:
	.word	PRIVATE_FUTEX - TLS_PRE_TCB_SIZE
#endif
	.align	2
.Lmunlock0:
	.long	__pthread_mutex_unlock_usercnt-.Lmunlock0b
.Lenable0:
	.long	__pthread_enable_asynccancel-.Lenable0b
.Ldisable0:
	.long	__pthread_disable_asynccancel-.Ldisable0b
.Lmlocki0:
	.long	__pthread_mutex_cond_lock-.Lmlocki0b

1:
	/* Initial locking failed.  */
	mov	r8, r5
#if cond_lock != 0
	add	#cond_lock, r5
#endif
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bf/s	99f
	 mov	#LLL_PRIVATE, r6
	mov	#LLL_SHARED, r6
99:
	extu.b	r6, r6
	mov.l	.Lwait0, r1
	bsrf	r1
	 mov	r2, r4
.Lwait0b:
	bra	2b
	 nop
3:
	/* Unlock in loop requires waekup.  */
	mov	r8, r4
#if cond_lock != 0
	add	#cond_lock, r4
#endif
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bf/s	99f
	 mov	#LLL_PRIVATE, r5
	mov	#LLL_SHARED, r5
99:
	mov.l	.Lwake0, r1
	bsrf	r1
	 extu.b	r5, r5
.Lwake0b:
	bra	4b
	 nop

5:
	/* Locking in loop failed.  */
	mov	r8, r5
#if cond_lock != 0
	add	#cond_lock, r5
#endif
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bf/s	99f
	 mov	#LLL_PRIVATE, r6
	mov	#LLL_SHARED, r6
99:
	extu.b	r6, r6
	mov.l	.Lwait1, r1
	bsrf	r1
	 mov	r2, r4
.Lwait1b:
	bra	6b
	 nop

10:
	/* Unlock after loop requires wakeup.  */
	mov	r8, r4
#if cond_lock != 0
	add	#cond_lock, r4
#endif
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bf/s	99f
	 mov	#LLL_PRIVATE, r5
	mov	#LLL_SHARED, r5
99:
	mov.l	.Lwake1, r1
	bsrf	r1
	 extu.b	r5, r5
.Lwake1b:
	bra	11b
	 nop

12:
	/* The initial unlocking of the mutex failed.  */
	mov.l	r0, @(12,r15)
#if cond_lock != 0
	DEC (@(cond_lock,r8), r2)
#else
	DEC (@r8, r2)
#endif
	tst	r2, r2
	bf	13f

	mov	r8, r4
#if cond_lock != 0
	add	#cond_lock, r4
#endif
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bf/s	99f
	 mov	#LLL_PRIVATE, r5
	mov	#LLL_SHARED, r5
99:
	mov.l	.Lwake2, r1
	bsrf	r1
	 extu.b	r5, r5
.Lwake2b:

13:
	bra	14b
	 mov.l	@(12,r15), r0

	.align	2
.Lwait0:
	.long	__lll_lock_wait-.Lwait0b
.Lwake0:
	.long	__lll_unlock_wake-.Lwake0b
.Lwait1:
	.long	__lll_lock_wait-.Lwait1b
.Lwake1:
	.long	__lll_unlock_wake-.Lwake1b
.Lwake2:
	.long	__lll_unlock_wake-.Lwake2b
	.size	__pthread_cond_wait, .-__pthread_cond_wait
versioned_symbol (libpthread, __pthread_cond_wait, pthread_cond_wait,
		  GLIBC_2_3_2)


	.type	__condvar_w_cleanup, @function
__condvar_w_cleanup:
	mov	r4, r11

	/* Get internal lock.  */
	mov	#0, r3
	mov	#1, r4
#if cond_lock != 0
	CMPXCHG (r3, @(cond_lock,r8), r4, r2)
#else
	CMPXCHG (r3, @r8, r4, r2)
#endif
	bt	1f
	 nop

	mov	r8, r5
#if cond_lock != 0
	add	#cond_lock, r5
#endif
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bf/s	99f
	 mov	#LLL_PRIVATE, r6
	mov	#LLL_SHARED, r6
99:
	extu.b	r6, r6
	mov.l	.Lwait3, r1
	bsrf	r1
	 mov	r2, r4
.Lwait3b:

1:
	mov.l	@(broadcast_seq,r8), r0
	mov.l	@(4,r15), r1
	cmp/eq	r0, r1
	bf	3f

	mov	#1, r2
	mov	#0, r3

	/* We increment the wakeup_seq counter only if it is lower than
	   total_seq.  If this is not the case the thread was woken and
	   then canceled.  In this case we ignore the signal.  */
	mov.l	@(total_seq+4,r8), r0
	mov.l	@(wakeup_seq+4,r8), r1
	cmp/hi	r1, r0
	bt/s	6f
	 cmp/hi	r0, r1
	bt	7f
	mov.l	@(total_seq,r8), r0
	mov.l	@(wakeup_seq,r8), r1
	cmp/hs	r0, r1
	bt	7f

6:
	clrt
	mov.l	@(wakeup_seq,r8),r0
	mov.l	@(wakeup_seq+4,r8),r1
	addc	r2, r0
	addc	r3, r1
	mov.l	r0,@(wakeup_seq,r8)
	mov.l	r1,@(wakeup_seq+4,r8)
	mov.l	@(cond_futex,r8),r0
	add	r2, r0
	mov.l	r0,@(cond_futex,r8)

7:
	clrt
	mov.l	@(woken_seq,r8),r0
	mov.l	@(woken_seq+4,r8),r1
	addc	r2, r0
	addc	r3, r1
	mov.l	r0,@(woken_seq,r8)
	mov.l	r1,@(woken_seq+4,r8)

3:
	mov	#(1 << nwaiters_shift), r2
	mov.l	@(cond_nwaiters,r8),r0
	sub	r2, r0
	mov.l	r0,@(cond_nwaiters,r8)

	/* Wake up a thread which wants to destroy the condvar object.  */
	mov	#0, r10
	mov.l	@(total_seq,r8),r0
	mov.l	@(total_seq+4,r8),r1
	and	r1, r0
	not	r0, r0
	cmp/eq	#0, r0
	bf/s	4f
	 mov	#((1 << nwaiters_shift) - 1), r1
	not	r1, r1
	mov.l	@(cond_nwaiters,r8),r0
	tst	r1, r0
	bf	4f

	mov	r8, r4
	add	#cond_nwaiters, r4
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bt/s	99f
	 mov	#FUTEX_WAKE, r5
#ifdef __ASSUME_PRIVATE_FUTEX
	mov	#(FUTEX_WAKE|FUTEX_PRIVATE_FLAG), r5
	extu.b	r5, r5
#else
	stc	gbr, r1
	mov.w	.Lpfoff1, r2
	add	r2, r1
	mov.l	@r1, r5
	mov	#FUTEX_WAKE, r0
	or	r0, r5
#endif
99:
	mov	#1, r6
	mov	#0, r7
	mov	#SYS_futex, r3
	extu.b	r3, r3
	trapa	#0x14
	SYSCALL_INST_PAD
	mov	#1, r10

4:
#if cond_lock != 0
	DEC (@(cond_lock,r8), r2)
#else
	DEC (@r8, r2)
#endif
	tst	r2, r2
	bt	2f

	mov	r8, r4
#if cond_lock != 0
	add	#cond_lock, r4
#endif
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bf/s	99f
	 mov	#LLL_PRIVATE, r5
	mov	#LLL_SHARED, r5
99:
	mov.l	.Lwake3, r1
	bsrf	r1
	 extu.b	r5, r5
.Lwake3b:

2:
	/* Wake up all waiters to make sure no signal gets lost.  */
	tst	r10, r10
	bf/s	5f
	 mov	r8, r4
	add	#cond_futex, r4
	mov.l	@(dep_mutex,r8), r0
	cmp/eq	#-1, r0
	bt/s	99f
	 mov	#FUTEX_WAKE, r5
#ifdef __ASSUME_PRIVATE_FUTEX
	mov	#(FUTEX_WAKE|FUTEX_PRIVATE_FLAG), r5
	extu.b	r5, r5
#else
	stc	gbr, r1
	mov.w	.Lpfoff1, r2
	add	r2, r1
	mov.l	@r1, r5
	mov	#FUTEX_WAKE, r0
	or	r0, r5
#endif
99:
	mov	#-1, r6
	shlr	r6		/* r6 = 0x7fffffff */
	mov	#0, r7
	mov	#SYS_futex, r3
	extu.b	r3, r3
	trapa	#0x14
	SYSCALL_INST_PAD

5:
        mov.l   .Lmlocki3, r1
        bsrf    r1
         mov     r9, r4
.Lmlocki3b:

.LcallUR:
	mov.l	.Lresume, r1
#ifdef PIC
	add	r12, r1
#endif
	jsr	@r1
	 mov	r11, r4
	sleep

#ifndef __ASSUME_PRIVATE_FUTEX
.Lpfoff1:
	.word	PRIVATE_FUTEX - TLS_PRE_TCB_SIZE
#endif
	.align	2
.Lwait3:
	.long   __lll_lock_wait-.Lwait3b
.Lwake3:
        .long   __lll_unlock_wake-.Lwake3b
.Lmlocki3:
	.long   __pthread_mutex_cond_lock-.Lmlocki3b
.Lresume:
#ifdef PIC
	.long	_Unwind_Resume@GOTOFF
#else
	.long	_Unwind_Resume
#endif
.LENDCODE:
	cfi_endproc
	.size	__condvar_w_cleanup, .-__condvar_w_cleanup


	.section .gcc_except_table,"a",@progbits
.LexceptSTART:
	.byte	DW_EH_PE_omit			! @LPStart format (omit)
	.byte	DW_EH_PE_omit			! @TType format (omit)
	.byte	DW_EH_PE_sdata4			! call-site format
	.uleb128 .Lcstend-.Lcstbegin
.Lcstbegin:
	.ualong	.LcleanupSTART-.LSTARTCODE
	.ualong	.LcleanupEND-.LcleanupSTART
	.ualong	__condvar_w_cleanup-.LSTARTCODE
	.uleb128  0
	.ualong	.LcallUR-.LSTARTCODE
	.ualong	.LENDCODE-.LcallUR
	.ualong	0
	.uleb128  0
.Lcstend:


#ifdef SHARED
	.hidden DW.ref.__gcc_personality_v0
	.weak   DW.ref.__gcc_personality_v0
	.section .gnu.linkonce.d.DW.ref.__gcc_personality_v0,"aw",@progbits
	.align 4
	.type   DW.ref.__gcc_personality_v0, @object
	.size   DW.ref.__gcc_personality_v0, 4
DW.ref.__gcc_personality_v0:
	.long   __gcc_personality_v0
#endif
