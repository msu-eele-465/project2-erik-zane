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
            bis.b   #00000101b, &P3DIR  ; choose 3.2 as clock and 3.3 as data, outputs as default
            bis.b   #00000101b, &P3OUT  ; (passively high)

            bic.w   #LOCKLPM5,&PM5CTL0       ; Unlock I/O pins
            
            mov.b   #136, R6     ; address of Real Time Clock (I think)
            mov.b   #2, R11     ; default value of status register
            mov.b   #0, R10     ; set perform_send operation to 0
            bis.b   #00000101b, P3OUT       ; set clock and data pins to high
            mov.w   #2004h, R4              ; 
            mov.w   #0, R12  ; use this register to track which RTC register read
            ; test Bit reads (zeroes)
            mov.b   #2, cur_secs
            mov.b   #2, cur_mins
            mov.b   #2, cur_hours
            mov.b   #2, temp
            NOP

main:
            NOP
            ;jl main
            ;jge Send_data
            ;NOP
            mov.w    #200, R5
            jmp wait
wait:
            dec.w    R5
            jnz wait 
            jmp start_address_send         
start_address_send:
            mov.b    R6, R7
            bic.b    #BIT0, P3OUT
            mov.w    #50, R5
            ;rla.b    R7 ; BSL R7
            jmp wait2
wait2:
            dec.w    R5
            jnz wait2
            jmp Send_data_start
Send_data_start:
            mov.b    #3, R11
            mov.b    #9, R9     ; send 7 bits of data (number should be 8 for this)
            jmp Send_data 
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
           bis.b        #BIT0, P3OUT 
           mov.b        #3, R11      ; wait to send next bit
           jmp          Send_data
Send_0:
           bic.b        #BIT0, P3OUT  
           mov.b        #3, R11      ; wait to send next bit
           jmp          Send_data
End_address_send: 
            bic.b   #00000001b, &P3OUT       ; keep output low
            cmp.w    #137, R6
            jge      start_read  ; start to read data if you just sent a read signal
            mov.w   #2005h, R13   ; base read register is 2004
            add.w   R12, R13   ; if you are reading seconds, R12 will be 0, minutes 1, hours 2, temp 3
            cmp.w   R13, R4    ; make sure you don't perform too many register address sends 
            jnz Send_time  ; if you have sent every byte you intended, return to first
            mov.b    #2, R9   
            cmp.w   #2008h, R4 ; increment slave address register unless it has reached 2007
            jge     reset_read ; otherwise, reset it to 2004 
            inc     R12
            jmp wait3
reset_read: 
            mov.w   #2004h, R4 ; reset send register to 2004 
            mov.w   #0, R12 ; reset register counter to 0
            jmp wait3
End_data:
            xor.b   #00000001b, &P3OUT       ; in case of read finish, send nack to terminate signal from slave
                                             ; in case of register send, do not send stop condition
            mov.w       #2, R11     ; stop send 
            mov.w       #1, R10
            xor.b       #00000001b, R6    ; read/write operations alternate
            jmp main
wait3:
            cmp.w    #4, R11       ; is "send next bit" bit toggled to 1 (r11 =4)?, if no, jump to Send_data
            jl  wait3       ; wait until negative clock edge to move past wait3
            mov.b   #3, R11 ; reset negative clock-edge tracker
            dec.b R9        ; decrement the number of negative clock edges remaining
            jz End_data     ; stop waiting if you've waited for two negative clock edges
            jmp wait3 
Send_time: 
            mov.b   @R4+, R7
            bic.b    #BIT0, P3OUT
            mov.w    #100, R5
            jmp Send_data_start

;------------------------------------------------------------------------------
;           Read data
;------------------------------------------------------------------------------
start_read: 
            bis.w   #LOCKLPM5,&PM5CTL0       ; lock I/O pins
            bic.b   #00000001b, &P3DIR       ; set P3.0 to input pulled low
            bis.b   #00000001b, &P3REN       ; enable resistors
            bic.b   #00000001b, &P3OUT       ; pull down resistor
            bic.w   #LOCKLPM5,&PM5CTL0       ; Unlock I/O pins
            mov.b   #3, R11           ; move #3 into R11
            mov.b   #0, R8            ; set R8 to 00000000b
            mov.w   #9, R9

read_next_bit:
            cmp.w    #4, R11       ; is "send next bit" bit toggled to 1 (r11 =4)?, if no, jump to Send_data
            jl  read_next_bit
            dec.b R9            ; Reduce Counter
            jz End_data_read
            rla.b   R8
            bit.b   #00000001b, &P3IN
            jnz     read_1
            jz      read_0

read_1:
            bis.b   #BIT0, R8
            mov.b        #3, R11      ; wait to send next bit
            jmp read_next_bit

read_0:
            bic.b   #BIT0, R8
            mov.b        #3, R11      ; wait to send next bit
            jmp read_next_bit

End_data_read:
            bis.w   #LOCKLPM5,&PM5CTL0       ; lock I/O pins
            bis.b   #00000001b, &P3DIR       ; set P3.0 to output
            bic.b   #00000001b, &P3REN       ; disable resistors
            bis.b   #00000001b, &P3OUT       ; send NACK
            bic.w   #LOCKLPM5,&PM5CTL0       ; Unlock I/O pins

            mov.w   R4, R14
            add.w   #4, R14    
            mov.b   R8, 0(R14)  ; store read data to appropriate location in memory
            mov.b   #2, R9
            jmp wait3 ; default at end of this operation


;------------------------------------------------------------------------------
;           Interrupt Service routines
;------------------------------------------------------------------------------
;---------- ISR_HeartBeat ------- 
ISR_HeartBeat:
            xor.b       #BIT0, &P1OUT      ; on interrupt, toggle green led
            bic.w       #CCIFG, &TB0CCTL0  ; clear interrupt flag
            reti                       ; return to code location prior to interrupt commands
;---------- End ISR_HeartBeat ------- 
; ---------- Clock_ISR -------- 
ISR_Clock: 
            cmp.b       #3, R11  ; is data being sent (is send status register (R11) empty (value greater than or equal to ~1))
            jge         Switch_Clock    ; if yes, then jump to switch_clock
            ;bis.b      #BIT2, P3OUT   ; set clock high as default
            cmp.b       #1, R10
            jge         End_send_clock
        ; also check if value is less than 2-- this will symbolize some type of send operation
Clear_Clock_Flag:
            bic.w       #CCIFG, &TB1CCTL0  ; clear interrupt flag
            reti                       ; return 
End_send_clock:
            bis.b       #BIT2, P3OUT   ; set clock high as default
            bis.b       #BIT0, P3OUT       ; set data pin to high as default
            mov.b       #0, R10
            jmp Clear_Clock_Flag
Switch_Clock:
            xor.b       #BIT2, P3OUT   ; toggle clock output
            xor.b       #00000001b, R10     ; set perform_send operation to 1
            cmp.b       #1, R10             ; compare R10, bit 1 of 0 means r10 is low => send next bit
            jge         Send_Next_Bit; if bit was toggled to low, toggle "send next bit" bit to 1 (jump to new subroutine to perform this operation, =>
            jmp         Clear_Clock_Flag
                ; => then jump to Clear_clock_flag)
Send_Next_Bit:
            mov.b       #4, R11  
            jmp         Clear_Clock_Flag
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

            .sect   ".int41"
            .short  ISR_Clock


;------------------------------------------------------------------------------
;           Memory Allocation
;------------------------------------------------------------------------------

            .data
            .retain
; initial time
Register_Seconds:        .short  0101100000000000b     ; 58 seconds
Minutes_Hours:           .short  0001001000110010b     ; 32 minutes
Read_Registers1:         .short  0000000100000000b     ; Register 1, Register 0
Read_Registers2:         .short  0001000100000010b     ; Register 11, Register 2

; updated time
cur_secs:       .space   1   ; 2009h 
cur_mins:       .space   1   ; 2008h
cur_hours:      .space   1   ; 200Bh
temp:           .space   1   ; 200Ah  (probably)