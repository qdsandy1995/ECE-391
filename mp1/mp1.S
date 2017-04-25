# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION=64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs
.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:

	pushl 	%ebp
	movl 	%esp,%ebp
	pushl	%esi					#following the c calling convention 
	pushl	%edi
	pushl	%ebx
	call		update_missiles		# save registers and start traversing the list 
	popl	%ebx
	popl	%edi
	popl	%esi
	
	leave
	ret
		


	
	
# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
        movl 8(%esp),%ebx
        cmpl $0,%ebx
        jl error
        cmpl $4,%ebx
        jg error
        jmp *jump_table(,%ebx,4)
        ret
error:
        movl $-1,%eax   #set return value to -1
        ret

jump_table: .long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

# ----------------- Functions private to this file -------------------

# update_missiles 
# this function traverse through the linked list and update the locations and drawings on the screen 
# Inputs   : none 
# Outputs  : none 
# Registers: Standard C calling convention

update_missiles:
        pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi
        movl mp1_missile_list,%ebx   # the head address of list is in ebx

first_function:
        cmpl $0,%ebx               # end of the list?
        je redraw_city
        cmpl $0,EXPLODED(%ebx)     # exploding?
        jne test_out_of_board

update_location:
        movl X(%ebx),%edx    #edx for X
        shrl $16,%edx
        imull $2,%edx
        movl Y(%ebx),%eax    #eax for Y
        shrl $16,%eax
        imull $160,%eax
        addl %edx,%eax

        movb $32,%cl     
        call mp1_poke          # remove previous missile
        movl VX(%ebx),%edx     # exi for VX
        addl %edx,X(%ebx)      # update X
        movl VY(%ebx),%eax     # edi for VY 
        addl %eax,Y(%ebx)      # update Y

        movl X(%ebx),%edx
        shrl $16,%edx
        imull $2,%edx
        movl Y(%ebx),%eax   
        shrl $16,%eax
        imull $160,%eax
        addl %edx,%eax
        movb C(%ebx),%cl #load the character
        pushl %edx
        call mp1_poke #redraw it at the new location
        popl %edx

  test_out_of_board:
        movl X(%ebx),%edx
        shrl $16,%edx
        movl Y(%ebx),%eax   
        shrl $16,%eax 
        cmpl $0,%edx
        jl mp1_missile_remove
        cmpl $79,%edx
        jg mp1_missile_remove
        cmpl $0,%eax
        jl mp1_missile_remove
        cmpl $24,%eax
        jg mp1_missile_remove

  exploding:
        cmpl $0,EXPLODED(%ebx)
        je check_destination
        
  while_exploding:
        pushl %ebx
        call missile_explode
        popl %ebx
        cmpl $0,%eax
        je deal_with_explosion           
        call mp1_notify_user

  deal_with_explosion:
        movl EXPLODED(%ebx),%eax      # decrement the explode field
        subl $1,%eax
        movl %eax,EXPLODED(%ebx)
        cmpl $0,EXPLODED(%ebx)   # see whether draw or erase
        je mp1_missile_remove

        movl X(%ebx),%edx    #edx for X
        shrl $16,%edx
        imull $2,%edx
        movl Y(%ebx),%eax    #eax for Y
        shrl $16,%eax
        imull $160,%eax
        addl %edx,%eax
        movb $32,%cl
        pushl %edx
        call mp1_poke         # remove the old missile
        popl %edx

        movl X(%ebx),%edx    #edx for X
        shrl $16,%edx
        imull $2,%edx
        movl Y(%ebx),%eax    #eax for Y
        shrl $16,%eax
        imull $160,%eax
        addl %edx,%eax
        movb $64,%cl         
        call mp1_poke         # draw the Explosion Character
        jmp finally

 check_destination:
        movl X(%ebx),%edx
        shrl $16,%edx
        cmpl DEST_X(%ebx),%edx
        jne finally
        movl Y(%ebx),%eax   
        shrl $16,%eax 
        cmpl DEST_Y(%ebx),%eax 
        jne finally
        jmp while_exploding       
		

finally:
        cmpl $0,NEXT(%ebx)     # check if at the end of the list
        je redraw_city
        movl NEXT(%ebx),%ebx    
        jmp first_function

mp1_missile_remove:
        movl X(%ebx),%edx    
        shrl $16,%edx
        imull $2,%edx
        movl Y(%ebx),%eax    
        shrl $16,%eax
        imull $160,%eax
        addl %edx,%eax
        movb $32,%cl
        call mp1_poke

        cmpl mp1_missile_list,%ebx   # check if the head of the list will be destroyed
        je whoops 
        movl mp1_missile_list,%eax
        jne remove_missile            

whoops:
        movl NEXT(%ebx),%esi
        movl %esi,mp1_missile_list # move the second element to head
        pushl %ebx
        call mp1_free
        popl %ebx
        movl mp1_missile_list,%ebx
        jmp first_function

remove_missile:
        cmpl NEXT(%eax),%ebx       # get the pointer before the missile        
        je loop_out
        movl NEXT(%eax),%eax
        jmp remove_missile
loop_out:
        movl NEXT(%ebx),%edi       # get the pointer after the missile
        movl %edi,NEXT(%eax) 
        pushl %eax
        pushl %ebx
        call mp1_free
        popl %ebx
        popl %eax
        movl %edi,%ebx       
        jmp first_function




redraw_city:
        movl base_alive, %ecx

first_base:        
        movl $1, %esi           # check first base
        cmpb $0, %cl
        je destroy_city
        jmp draw_city

second_base:
        movl $2, %esi           # check second base
        cmpb $0, %ch
        je destroy_city
        jmp draw_city

third_base:
        movl $3, %esi           # check third base
        shrl $8, %ecx
        cmpb $0, %ch
        je destroy_city
        jmp draw_city
        
destroy_city:
        xorl %edx, %edx
        movl $dead_base_pic, %edi  

destroy_loop:
        movb (%edi), %cl                 # store the first char
        imull $40,%esi, %eax             # get the location
        addl $3836, %eax                 #offset
        addl %edx, %eax
        addl %edx, %eax
        pushl %edx
        call mp1_poke
        popl %edx
		addl $1, %edi
        addl $1, %edx
        cmpl $5,%edx
        jne destroy_loop
        cmpl $1,%esi
        je second_base
        cmpl $2,%esi
        je third_base
        jmp draw_crosshairs

draw_city:
        xorl %edx,%edx
        movl $base_pic, %edi

draw_loop:
        movb (%edi),%cl                 # store the first char
        imull $40,%esi,%eax             # get the location
        addl $3836,%eax                 #offset
        addl %edx,%eax
        addl %edx,%eax
        pushl %edx
        call mp1_poke
        popl %edx
		addl $1,%edi
        addl $1,%edx
        cmpl $5,%edx
        jne draw_loop
        cmpl $1,%esi
        je second_base
        cmpl $2,%esi
        je third_base
        jmp draw_crosshairs

draw_crosshairs:
        movb $43,%cl
        imull $2,crosshairs_x,%edx
        imull $160,crosshairs_y,%eax
        addl %edx,%eax
        call mp1_poke
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret


#########################################
# mp1_ioctl_startgame
	

mp1_ioctl_startgame:
	pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl $0,mp1_missile_list       # initialize list
        movl $0,base_alive
        notl base_alive                # set base_alive to 1
        movl $0,mp1_score              # initialize score
        movl $40,crosshairs_x
        movl $12,crosshairs_y

        popl %edi
        popl %esi
        popl %ebx
        leave
        ret

###################################
# mp1_ioctl_addmissile
	
mp1_ioctl_addmissile:
        pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        cmpl $0,8(%ebp) # check if (user missile == NULL)
        je missile_null

        movl 8(%ebp),%edi # user_missile stored at edi
        movl $33,%edx   # 33 bytes in one missile
        pushl %edx
        call mp1_malloc
        popl %edx
        cmpl $0,%eax    # check the void pointer
        je missile_null

        movl %eax,%esi  # move the memlocation to %esi
        pushl %edx      # long data_argument == 33
        pushl %edi      # from ptr
        pushl %esi      # to ptr
        call mp1_copy_from_user
        popl %esi
        popl %edi
        popl %edx

        cmpl $0,%eax    # copy successful?
        jne copy_failed
		
        movl mp1_missile_list,%ebx
        movl %ebx,NEXT(%esi)
        movl %esi, mp1_missile_list # new missile added to the top of the list
        popl %edi
        popl %esi
        popl %ebx
        leave
	    ret

missile_null:
        movl $-1,%eax
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret

copy_failed:
        pushl %esi
        call mp1_free
        popl %esi
        movl $-1,%eax
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret
	
#############################
# mp1_ioctl_movexhairs

mp1_ioctl_movexhairs:
        pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        movl crosshairs_x,%edx
        movl crosshairs_y,%eax
        imull $160,%eax
        imull $2,%edx
        addl %edx,%eax
        movb $32,%cl
        call mp1_poke           #remove the old crosshair

        movl 8(%ebp),%eax       #store the x,y change in eax
        addw %ax,crosshairs_x   #update x
        shrl $16,%eax           #get the higher 16 bits(y)
        addw %ax,crosshairs_y   #update y
        movl crosshairs_x,%edx 
        movl crosshairs_y,%eax

check_left:        
        cmpl $0,%edx
        jge check_right
        movl $0,crosshairs_x
check_right:
        cmpl $79,%edx
        jle check_down
        movl $79,crosshairs_x
check_down:
        cmpl $0,%eax
        jge check_up
        movl $0,crosshairs_y
check_up:
        cmpl $24,%eax
        jle redraw_crosshair
        movl $24,crosshairs_y
        
redraw_crosshair:
        movl crosshairs_x,%edx  
        movl crosshairs_y,%eax  
        imull $160,%eax
        imull $2,%edx
        addl %edx,%eax          # get the location
        movb $43,%cl
        call mp1_poke
        
        xorl %eax,%eax          # return 0
        popl %edi
        popl %esi
        popl %ebx
        leave
	ret

################################
# mp1_ioctl_getstatus

mp1_ioctl_getstatus:

	pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi

        cmpl $0,8(%ebp)
        je failed

        movl $4,%edx         
        pushl %edx
        call mp1_malloc
        popl %edx

        cmpl $0,%eax
        je failed
        movl %eax,%esi       # %esi has the address now

store_city:
        xorl %ecx,%ecx
        movl base_alive,%eax
check_first:
        cmpb $0,%al
        je check_second
        orl $1,%ecx
check_second:
        cmpb $0,%ah
        je check_third
        orl $2,%ecx
check_third:
        shrl $8,%eax
        cmpb $0,%ah
        je check_score
        orl $4,%ecx
check_score:
        shll $16,%ecx
        addl mp1_score,%ecx
        movl %ecx,(%esi)
        movl 8(%ebp),%edi

        pushl %edx             # data_argument
        pushl %esi             # ptr from
        pushl %edi             # ptr to
        call mp1_copy_to_user
        popl %edi
        popl %esi
        popl %edx

        cmpl $0,%eax
        jne fail_copy

        pushl %esi
        call mp1_free
        popl %esi

        xorl %eax,%eax
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret

fail_copy:
        pushl %esi
        call mp1_free
        popl %esi
        movl $-1,%eax
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret
failed:
        movl -1,%eax
        popl %edi
        popl %esi
        popl %ebx
        leave
		ret

############################
# mp1_ioctl_endgame

	
mp1_ioctl_endgame:
	pushl %ebp
        movl %esp,%ebp
        pushl %ebx
        pushl %esi
        pushl %edi
		
        movl mp1_missile_list,%edx
clean_up:
        cmpl $0,%edx
        je finished
        movl NEXT(%edx),%esi
        pushl %edx
        call mp1_free
        popl %edx
        movl %esi,%edx
        jmp clean_up
finished:
        xorl %eax,%eax
        popl %edi
        popl %esi
        popl %ebx
        leave
        ret
