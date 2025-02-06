; Zane Lewis and Erik Moore
;-------------------------------------------------------------------------------
            		.cdecls C,LIST,"msp430.h"       ; Include device header file          
;-------------------------------------------------------------------------------
            		.def    RESET                   ; Export program entry-point to
                                            		; make it known to linker.
            		.global __STACK_END
            		.sect   .stack                  ; Make stack linker segment ?known?

            		.text                           ; Assemble to Flash memory
            		.retain                         ; Ensure current section gets linked
            		.retainrefs                     
                                            		
RESET       		mov.w   #__STACK_END,SP         ; Initialize stack pointer
StopWDT     		mov.w   #WDTPW|WDTHOLD,&WDTCTL  ; Stop WDT
;-------------------------------------------------------------------------------
init:
					bis.b	#BIT2, &P3DIR			; set P3.2 as out for SCL
					bic.b	#BIT2, &P3OUT			; set init val to 0

					bis.b	#BIT0, &P3DIR			; set P3.0 as out for SDA
					bic.b	#BIT0, &P3OUT			; set init val to 0

                    bic.b   #BIT6, &P6OUT           ; Clear P6.6 output
                    bis.b   #BIT6, &P6DIR           ; P6.6 output

					bic.b	#LOCKLPM5, &PM5CTL0		; disable DIO low-power default

                    bis.w   #TBCLR, &TB0CTL         ; Clears Timer B0
                    bis.w   #TBSSEL__ACLK, &TB0CTL  ; Select ACLK as clock (32.768 kHz)
                    bis.w   #MC__UP, &TB0CTL        ; Sets Timer B0 to Up
                    mov.w   #32768, &TB0CCR0        ; Sets CCR0 for 1s
                    bis.w   #CCIE, &TB0CCTL0        ; Enables CCR0 interrupt
                    bic.w   #CCIFG, &TB0CCTL0       ; Clears interrupt flag

                    NOP
                    bis.w   #GIE, SR		        ; Enables global interrupts
                    NOP

main:
					; RTC address plus write and register address
					call 	#i2c_start				; start condition
					mov.b	transmit_byte, R8		; i2c address into R8
					clrc							; read/write bit set/clear C then rotate with carry
					rlc.b 	R8						; rotate R8 to append W/R bit to end
					call	#i2c_send				; send address
					tst.b	R12						; tests to see if the MSP received a NACK
					jnz		nack_en					; if the MSP received a NACK jump
					mov.b	seconds_register, R8	; move the value of the seconds_register into R8
					call 	#i2c_send				; sends seconds register address
					tst.b	R12						; tests to see if the MSP received a NACK
					jnz		nack_en					; if the MSP received a NACK then jump
					call	#i2c_stop				; sends i2c stop condition

					; RTC address plus read and data
					call	#i2c_start
					mov.b	transmit_byte, R8		; i2c address into R8
					setc							; read/write bit set/clear C then rotates with carry
					rlc.b 	R8						; rotates R8 to append W/R bit to end
					call	#i2c_send				; send address
					tst.b	R12						; tests to see if the MSP received a NACK
					jnz		nack_en					; if the MSP received a NACK then jump
					call	#i2c_receive
					call	#i2c_stop				; sends i2c stop condition

					mov.b	seconds, R13
					mov.b	minutes, R14
					mov.b	hours, R15

					; sets register pointer to temperature MSB (0x11)
					call    #i2c_start
					mov.b   transmit_byte, R8       ; i2c address into R8
					clrc                            ; clear R/W bit (write)
					rlc.b   R8                      ; rotate to append the W/R bit
					call    #i2c_send               ; send address
					mov.b   #0x11, R8               ; register address for temperature MSB
					call    #i2c_send               ; sends register address
					call    #i2c_stop               ; sends the stop condition

					; reads temperature MSB and LSB
					call    #i2c_start
					mov.b   transmit_byte, R8       ; i2c address into R8
					setc                            ; sets thr R/W bit (read)
					rlc.b   R8                      ; rotates to append the W/R bit
					call    #i2c_send               ; send address
					call    #i2c_rx_byte            ; reads the MSB
					mov.b   R10, temp_msb           ; stores the MSB
					call    #ack                    ; sends ACK
					call    #i2c_rx_byte            ; reads the LSB
					mov.b   R10, temp_lsb           ; stores the LSB
					call    #nack                   ; sends NACK to end the transaction
					call    #i2c_stop               ; sends the stop condition

					jmp 	main
					nop
nack_en:
					call	#i2c_stop
					jmp 	main
					nop

;-------------------------------------------------------------------------------
; Subroutines
;-------------------------------------------------------------------------------
; Delay
short_delay:		mov.w	short_outer_delay, R4	; sets the outer loop delay
					mov.w	short_inner_delay, R6
					jmp		inner_loop
delay:				mov.w	outer_delay, R4			; sets the outer loop delay
					mov.w	inner_delay, R6
					jmp 	inner_loop
inner_loop:			mov.w	R6, R5					; sets the inner loop delay
					jmp		decr_inner
decr_inner:			dec		R5						; decrements the inner delay
					jnz		decr_inner				; if R5 is not 0 then it loops
					dec		R4						; decrements the outer delay
					jnz		inner_loop				; if R4 is not 0 then it loops
					ret								; return

i2c_start:			; SCL is high and SDA needs to swap from high to low. SCL needs to go low
					call 	#delay
					bic.b	#BIT0, &P3OUT			; SDA
					call 	#delay
					bic.b	#BIT2, &P3OUT			; SCL
					call 	#delay
					ret								; return

i2c_stop:
					bis.b	#BIT2, &P3OUT			; sets SCL high
					call	#delay
					bis.b	#BIT0, &P3OUT			; sets SDA high
					call 	#delay					; these extra delays are to seperate packets
					call 	#delay
					call 	#delay
					call 	#delay
					call 	#delay
					call 	#delay
					ret								; return

i2c_send:
					call	#i2c_tx_byte
					call 	#receive_ack
					ret								; return

i2c_tx_byte:
					mov.b	#08h, R7				; 08h sends 8 bits for the loop counter
tx_byte_for:		dec.b	R7
					mov.b	#080h, R9				; 1000 0000 0000 0000b = 080000h, 1000 0000 = 080h
					; begins sending bit
					and.b	R8, R9					; R8 stores byte data for transmit
					jz		sda_low					; if z=1 then MSB is 0 and we dont need to set SDA
					bis.b	#BIT0, &P3OUT			; sets SDA high
					jmp		stability_delay			; skips to the stability delay
sda_low:			bic.b	#BIT0, &P3OUT			; sets SDA low
stability_delay:	call	#clock_pulse
					bic.b	#BIT0, &P3OUT			; sets SDA low
					call	#delay
					; ends the send bit
					rla.b	R8						; rotate byte to next bit
tx_byte_for_cmp:	cmp		#00h, R7				; compare R7 to 0
					jnz		tx_byte_for				; if R7 is not 0 then continue iterating through
					ret								; return

receive_ack:	
					bis.b	#BIT0, &P3OUT			; sets SDA high
					bic.b	#BIT0, &P3DIR			; sets SDA as input
					call	#short_delay			; short delay for stability
					bis.b	#BIT2, &P3OUT			; sets SCL high
					; checks ack/nack
					bit.b	#BIT0, &P3IN			; this tests the value of P3.0, if z=1 we have a nack, if z=0 we have an ack
					jz		received_ack
received_nack:		mov.b	#01h, R12
					jmp 	final_receive
received_ack:		mov.b	#00h, R12
final_receive:		call 	#clock_pulse_halved
					bis.b	#BIT0, &P3DIR			; sets SDA as output
					bic.b	#BIT0, &P3OUT			; sets SDA low
					call	#short_delay			; short delay for stability
					ret								; return

i2c_receive:		; the i2c_receive receives 3 bytes, writes them to memory, then sends either ack or nack if applicable
					call	#i2c_rx_byte
					mov.b	R10, seconds
					call 	#ack
					call	#i2c_rx_byte
					mov.b	R10, minutes
					call 	#ack
					call	#i2c_rx_byte
					mov.b	R10, hours
					call 	#nack
					ret								; return

i2c_rx_byte:
					mov.b	#08h, R7				; 08h sends 8 bits for the loop counter
					mov.w	#00h, R10
					bic.b	#BIT0, &P3DIR
rx_byte_for:		dec.b	R7
					call	#short_delay			; short delay for stability
					bis.b	#BIT2, &P3OUT			; sets SCL high
					bit.b	#BIT0, &P3IN			; this tests the value of P3.0, if z=1 then we have a 0, if z=0 we have a 1
					jz		rx_0				
rx_1:				setc
					jmp		rx_delay
rx_0:				clrc
rx_delay:			rlc.b	R10
					call 	#clock_pulse_halved		; half pulse for SCL
					call	#delay					; calls delay
					cmp		#00h, R7				; compares R7 to 0
					jnz		rx_byte_for				; if R7 is not 0 then continue iterating through
					bis.b	#BIT0, &P3DIR
					ret								; return

ack:			
					bic.b	#BIT0, &P3OUT			; sets the SDA low
					call	#clock_pulse			; SCL full pulse
					ret								; return

nack:			
					bis.b	#BIT0, &P3OUT			; sets SDA high
					call	#clock_pulse			; SCL full pulse
					bic.b	#BIT0, &P3OUT			; sets SDA low
					ret								; return

clock_pulse:		; SCL full pulse
					call	#short_delay			; short delay for stability
					bis.b	#BIT2, &P3OUT			; sets SCL high
					call 	#delay					; delay for bit
					bic.b	#BIT2, &P3OUT			; sets SCL low
					call	#short_delay			; short delay for stability
					ret								; return

clock_pulse_halved:	; half pulse for SCL
					call 	#delay					; delay for bit
					bic.b	#BIT2, &P3OUT			; sets SCL low
					call	#short_delay			; short delay for stability
					ret								; return

;-------------------------------------------------------------------------------
; 	    Timer B0 CCR0 ISR
;-------------------------------------------------------------------------------
TimerB0_ISR xor.b   #BIT6, &P6OUT                  ; Toggle P6.6
 	        bic.w   #CCIFG, &TB0CCTL0              ; Clears interrupt flag
            reti                                   ; Return

;-------------------------------------------------------------------------------
; Memory Allocation
;-------------------------------------------------------------------------------
					.data
					.retain

short_outer_delay:	.short	00001h
short_inner_delay:	.short  00001h
outer_delay:		.short	000005h
inner_delay:		.short  00002h

transmit_byte:		.byte  	00068h					; the DS3231's address is 1101000 = 068h
seconds_register: 	.byte	00000h					; register for seconds address on the DS3231
seconds:			.byte	00000h
minutes:			.byte	00000h
hours:				.byte	00000h
temp_msb:			.byte	00000h                  ; Temperature's MSB
temp_lsb:			.byte	00000h                  ; Temperature's LSB
     
;-------------------------------------------------------------------------------
; Interrupt Vectors
;-------------------------------------------------------------------------------
	            	.sect   ".reset"                ; MSP430 RESET Vector
	            	.short  RESET

                    .sect   ".int43"                
                    .short  TimerB0_ISR             ; Timer B0 CCR0 Interrupt Vector