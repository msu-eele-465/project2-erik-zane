;-------------------------------------------------------------------------------
; Include files
            .cdecls C,LIST,"msp430.h"  ; Include device header file
;-------------------------------------------------------------------------------

            .def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.

            .global __STACK_END
            .sect   .stack                  ; Make stack linker segment ?known?

            .text                           ; Assemble to Flash memory
            .retain                         ; Ensure current section gets linked
            .retainrefs

RESET       mov.w   #__STACK_END,SP         ; Initialize stack pointer
StopWDT     mov.w   #WDTPW+WDTHOLD,&WDTCTL  ; Stop WDT
; 1 = read, 0 = write
; code for later, as we will likely need to switch our pins between input and output:
; (port and pin numbers are placeholders pins not typically enabled for I2C module use)
; setting pins as output:
; bis.w   #LOCKLPM5,&PM5CTL0 
; bis.b   #00001100b, &P3DIR  ; choose 3.3 as clock and 3.2 as data
; bis.b   #00001100b, &P3OUT  (passively high)
; bic.w   #LOCKLPM5,&PM5CTL0 

;setting pins as input:
; bis.w   #LOCKLPM5,&PM5CTL0 
; bic.b   #00001100b, &P3DIR
; bis.b   #00001100b, &P3REN
; bic.b   #00001100b, &P3OUT  (pull down resistors, for now)
; bic.w   #LOCKLPM5,&PM5CTL0 



init_heartbeat:
            bic.b   #BIT0,&P1OUT            ; Clear P1.0 output
            bis.b   #BIT0,&P1DIR            ; P1.0 output


            bis.w   #TBCLR, &TB0CTL         ; 
            bis.w   #TBSSEL__ACLK, &TB0CTL  ; choose ACLK
            bis.w   #MC__UP, &TB0CTL        ; choose UP counting

            mov.w   #32778, &TB0CCR0        ; count to 32778 (1 second), no dividers needed
            bis.w   #CCIE, &TB0CCTL0        ; enable interrput on TB0CCTL0
            bic.w   #CCIFG, &TB0CCTL0       ; clear interrupt flag

init: 
            ; switches
            bic.b   #001000b, &P2DIR ; switch 2
            bis.b   #001000b, &P2REN
            bic.b   #001000b, &P2OUT  ; (pull down resistors, for now)


            bic.b   #00000010b, &P4DIR ; switch 1
            bis.b   #00000010b, &P4REN
            bis.b   #00000010b, &P4OUT  ; (pull down resistors, for now)
            bis.b   #00000010b, &P4IES
            bic.b   #00000010b, &P4IFG
            bis.b   #00000010b, &P4IE

            bis.w   #TBCLR, &TB1CTL         ; clock_clock on control register TB1CTL
            bis.w   #TBSSEL__SMCLK, &TB1CTL  ; choose SMCLK
            bis.w   #MC__UP, &TB1CTL        ; choose UP counting

            mov.w   #100, &TB1CCR0        ; count to 100 (1/10,000 second), no dividers needed
            bis.w   #CCIE, &TB1CCTL0        ; enable interrput on TB0CCTL0
            bic.w   #CCIFG, &TB1CCTL0       ; clear interrupt flag

            NOP
            bis.w   #GIE, SR                ; enable global interrupts
            NOP

            ; Select I2C pins 
            bis.b   #00001100b, &P3DIR  ; choose 3.2 as clock and 3.3 as data, outputs as default
            bis.b   #00001100b, &P3OUT  ; (passively high)

            bic.w   #LOCKLPM5,&PM5CTL0       ; Unlock I/O pins
            
            mov.b   #68, R6     ; address of Real Time Clock (I think)
            mov.b   #2, R11     ; default value of status register
            mov.b   #0, R10     ; set perform_send operation to 0
            bis.b    #BIT2, P3OUT       ; set clock pin to high
            bis.b    #BIT3, P3OUT       ; set data pin to high
            NOP

main:
            NOP
            cmp.b    #1, R10
            jl main
            jge Send_data
            NOP
start:
            
stop:
            
tx_ack:
rx_ack:
tx_byte:
rx_byte:
sda_delay:
scl_delay:
send_address:
write:
read:
;------------------------------------------------------------------------------
;           Interrupt Service routines
;------------------------------------------------------------------------------
;---------- ISR_HeartBeat ------- 
ISR_HeartBeat:
        xor.b   #BIT0, &P1OUT      ; on interrupt, toggle green led
        bic.w   #CCIFG, &TB0CCTL0  ; clear interrupt flag
        reti                       ; return to code location prior to interrupt commands
;---------- End ISR_HeartBeat ------- 
; ---------- Switch1_ISR -------- 
Switch1_ISR:
            bic.b    #BIT3, P3OUT
            mov.w    #100, R5
wait:
            dec.w    R5
            jnz wait
Send_data_start:
            mov.b    R6, R7
            mov.b    #3, R11
            mov.b    #9, R9     ; send 7 bits of data (number should be 8 for this)
            rla.b    R7 ; BSL R7
            bis.b   #00000001b, R10     ; set perform_send operation to 1
            jmp Clear_SW1_Flag
Clear_SW1_Flag:
            bic.b    #BIT1, P4IFG
            reti       
Send_data:
            cmp.w    #4, R11       ; is "send next bit" bit toggled to 1 (r11 =4)?, if no, jump to Send_data
            jl  Send_data 
            dec.b R9            ; Reduce Counter
            jz End_address_send   ; if counter has reached 0, clear flag (for now)
            rla.b    R7
            jc  Send_1
            jnc Send_0
            ; otherwise, BSL and change pin (3.3) value to shifted-out bit
            ; decrement bit-send counter (R9)
            ; jnz send_data
Send_1:
           bis.b    #BIT3, P3OUT 
           mov.b    #3, R11      ; wait to send next bit
           jmp Send_data
Send_0:
           bic.b    #BIT3, P3OUT  
           mov.b    #3, R11      ; wait to send next bit
           jmp Send_data
End_address_send: 
            mov.w    #2, R11     ; default value of send-data status register (we will not ever send a larger number than 68)
            mov.w    #0, R10
            bis.b    #BIT2, P3OUT       ; set clock pin to high
            bis.b    #BIT3, P3OUT       ; set data pin to high
            jmp main

; ------ end Switch1_ISR ----------
; ---------- Clock_ISR -------- 
ISR_Clock: 
            cmp.b   #3, R11  ; is data being sent (is send status register (R11) empty (value greater than or equal to ~1))
            jge     Switch_Clock    ; if yes, then jump to switch_clock
            bis.b    #BIT2, P3OUT   ; set clock high as default
        ; also check if value is less than 2-- this will symbolize some type of send operation
Clear_Clock_Flag:
            bic.w   #CCIFG, &TB1CCTL0  ; clear interrupt flag
            reti                       ; return 

Switch_Clock:
            xor.b    #BIT2, P3OUT   ; toggle clock output
            xor.b   #00000010b, R10     ; set perform_send operation to 1
            cmp.b   #2, R10             ; compare R10, bit 1 of 0 means r10 is low
            jge Send_Next_Bit; if bit was toggled to low, toggle "send next bit" bit to 1 (jump to new subroutine to perform this operation, =>
            jmp Clear_Clock_Flag
                ; => then jump to Clear_clock_flag)
Send_Next_Bit:
            mov.b    #4, R11  
            jmp Clear_Clock_Flag
            NOP
        ; jump to clear clock flag
; ---------- end Clock_ISR -------- 
;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect   RESET_VECTOR            ; MSP430 RESET Vector
            .short  RESET                   ;

            .sect   ".int43"
            .short  ISR_HeartBeat

            .sect   ".int22"
            .short  Switch1_ISR

            .sect   ".int41"
            .short  ISR_Clock



; switch 1 is pressed:
; 1. SDA (P3.2) moves low
; 2. wait 1/10,000 of a second
; 3. begin clock operations (move data to send register)
; 4. clock moves low (passive)
; 5. send first bit of data (address)
; 6. clock moves high, then low
; 7. repeat steps 5-6 six more times