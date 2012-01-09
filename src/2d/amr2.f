c
c ----------------------------------------------------------------
c
       program amr2
c
c  Use adaptive mesh refinement to solve the hyperbolic 2-d equation:
c
c              u  +  f(u)    + g(u)   = 0
c               t         x        y
c
c or the more general non-conservation law form:
c              u  +  A u     + B u    = 0
c               t         x        y
c
c  using the wave propagation method as in CLAWPACK in combination
c  with the locally uniform embedded grids of AMR.

c  Estimate error with Richardson extrap. (in errest.f)
c  + gradient checking (in errsp.f).  Initial conditions set
c  in (qinit.f), b.c.'s in (physbd.f).

c  Specify rectangular domain from
c           (xlower,ylower) to (xupper,yupper).
c
c
c =========================================================================
c
c  This software is made available for research and instructional use only.
c  You may copy and use this software without charge for these non-commercial
c  purposes, provided that the copyright notice and associated text is
c  reproduced on all copies.  For all other uses (including distribution of
c  modified versions), please contact the author at the address given below.
c
c  *** This software is made available "as is" without any assurance that it
c  *** will work for your purposes.  The software may in fact have defects, so
c  *** use the software at your own risk.
c
c  --------------------------------------
c    AMRCLAW Version 5.0,  2012
c    Homepage: http://www.clawpack.org
c  --------------------------------------
c
c   Authors:
c
c             Marsha J. Berger
c             Courant Institute of Mathematical Sciences
c             New York University
c             251 Mercer St.
c             New York, NY 10012
c             berger@cims.nyu.edu
c
c             Randall J. LeVeque
c             Applied Mathematics
c             Box 352420
c             University of Washington,
c             Seattle, WA 98195-2420
c             rjl@uw.edu
c
c =========================================================================
c


c
c ----------------------------------------------------------------
c
      use amr_module
      implicit double precision (a-h,o-z)

      include "gauges.i"
      include "regions.i"

      common /combc2/ mthbc(4)
      common /comfine/ dxmin,dymin

      character * 12     pltfile,infile,outfile,dbugfile,matfile
      character * 20     parmfile
      character * 25 fname
      logical            vtime,rest,flag_richardson,flag_gradient
      integer            verbosity_regrid
      dimension          tout(maxout)
      dimension          tchk(maxout)

      integer oldmode,omp_get_max_threads
c
c
c  you may want to turn this on for SUN workstation, or replace
c  set to signal on overflow, divide by zero, and illegal operation
c
c       oldmode = ieee_handler("set","common",SIGFPE_ABORT)
c       if (oldmode .ne. 0) then
c           write(outunit,*)' could not set ieee trapper '
c           write(*,*)      ' could not set ieee trapper '
c           stop
c        endif
c
      infile   = 'amr2ez.data'
      outfile  = 'fort.amr'
      dbugfile = 'fort.debug'
      matfile  = 'fort.nplot'
      parmfile  = 'fort.parameters'

      open(dbugunit,file=dbugfile,status='unknown',form='formatted')
      open(parmunit,file=parmfile,status='unknown',form='formatted')
c
c     ## New in 4.4:  
c     ## Open file and skip over leading lines with # comments:
      fname = 'amrclaw.data'
      call opendatafile(inunit,fname)
c
      open(10,file='fort.info',status='unknown',form='formatted')
c
c
c     Number of space dimensions:  
      read(inunit,*) ndim  
      if (ndim .ne. 2) then
          write(outunit,*)
     &       'Error ***   ndim = 2 is required,  ndim = ',ndim
          write(outunit,*) '*** Are you sure input has been converted'
          write(outunit,*) '*** to Clawpack 5.x form?'
          stop
      endif
          
c
c
c     domain variables
      read(inunit,*) nx
      read(inunit,*) ny
      read(inunit,*) mxnest
      if (mxnext .le. 0) then
          write(outunit,*)
     &       'Error ***   mxnest (amrlevels_max) <= 0 not allowed'
         stop
      endif
          
      if (mxnest .gt. maxlv) then
         write(outunit,*)
     &    'Error ***   mxnest > max. allowable levels (maxlv) in common'
         write(*,*)
     &    'Error ***   mxnest > max. allowable levels (maxlv) in common'
         stop
      endif
      
      !# anisotropic refinement always allowed in 5.x:
      read(inunit,*) (intratx(i),i=1,max(1,mxnest-1))
      read(inunit,*) (intraty(i),i=1,max(1,mxnest-1))
      read(inunit,*) (kratio(i), i=1,max(1,mxnest-1))
      
          
c      if (intrat(1) .lt. 0) then
c          # this flags the situation where we do not want to refine in t
c           write(6,*) '*** No refinement in time!'
c           intrat(1) = -intrat(1)
c           do i=1,max(1,mxnest-1)
c              kratio(i) = 1
c              enddo
c        else
c          # the normal situation is to refine dt by same factors as dx,dy
c           do i=1,max(1,mxnest-1)
c              kratio(i) = intrat(i)
c              enddo
c        endif

      read(inunit,*) t0
      tstart = t0                 ! for common block  !! FIX? !!

      read(inunit,*) outstyle
        if (outstyle.eq.1) then
           read(inunit,*) nout
           read(inunit,*) tfinal
c          # array tout is set below
           iout = 0
           endif
        if (outstyle.eq.2) then
           read(inunit,*) nout
           read(inunit,*) (tout(i), i=1,nout)
           iout = 0
           endif
        if (outstyle.eq.3) then
           read(inunit,*) iout
           read(inunit,*) nout
           endif
        if (outstyle.eq.4) then
           read(inunit,*) dtout
           read(inunit,*) tfinal
           nout = floor((tfinal - t0)/dtout)
           if (dabs(nout*dtout - (tfinal-t0))
     &         .gt.1.d-12*(tfinal-t0)) then
              tfinal = t0 + nout*dtout
              write(outunit,*) "*** dtout does not divide tfinal-t0"
              write(outunit,*) "*** resetting tfinal to ", tfinal
              endif
c          # array tout is set below
           endif

      if (nout .gt. maxout) then
         write(outunit,*) 'Error ***   nout > maxout in common'
         write(*,*)       'Error ***   nout > maxout in common'
         stop
      endif

      if ((outstyle.eq.1) .or. (outstyle.eq.4)) then
	   do i=1,nout
	      tout(i) = t0 + i*(tfinal-t0)/float(nout)
	      enddo
       endif

      print *, '+++ iout = ',iout
      print *, '+++ nout = ',nout
      print *, '+++ tout = ',(tout(i),i=1,nout)

      read(inunit,*) possk(1)   ! dt_initial
      read(inunit,*) dtv2       ! dt_max
      read(inunit,*) cflv1      ! cfl_max
      read(inunit,*) cfl        ! clf_desired
      read(inunit,*) nv1        ! steps_max
      if (outstyle.eq.1 .or. outstyle.eq.2) then
         nstop = nv1
         endif

      read(inunit,*) vtime      ! dt_variable
      if (vtime) then
         method(1) = 2
       else
         method(1) = 1
       endif

      read(inunit,*) method(2)  ! order
      iorder = method(2)
      read(inunit,*) method(3)  ! order_trans

      read(inunit,*) dimensional_split
      if (dimensional_split.gt.0) then
         write(6,*) '*** ERROR ***  dimensional_split = ',
     &               dimensional_split
         write(6,*) ' dimensional splitting not supported in amrclaw'
         stop
         endif

      read(inunit,*) method(4)   ! verbosity
      read(inunit,*) method(5)   ! src_split
      read(inunit,*) mcapa1
      read(inunit,*) naux
      if (naux .gt. maxaux) then
         write(outunit,*) 'Error ***   naux > maxaux'
         write(*,*)       'Error ***   naux > maxaux'
         stop
      endif
      do iaux = 1, naux
         read(inunit,*) auxtype(iaux)
      end do

      read(inunit,*) nvar    ! meqn
      read(inunit,*) mwaves
      if (mwaves .gt. maxwave) then
         write(outunit,*) 'Error ***   mwaves > maxwave'
         write(*,*)       'Error ***   mwaves > maxwave'
         stop
      endif
      read(inunit,*) (mthlim(mw), mw=1,mwaves)
      read(inunit,*) ifwave

      read(inunit,*) xlower
      read(inunit,*) xupper
      read(inunit,*) ylower
      read(inunit,*) yupper

      read(inunit,*) nghost
      read(inunit,*) mthbc(1)
      read(inunit,*) mthbc(2)
      read(inunit,*) mthbc(3)
      read(inunit,*) mthbc(4)

c     1 = left, 2 = right 3 = bottom 4 = top boundary
      xperdom = (mthbc(1).eq.2 .and. mthbc(2).eq.2)
      yperdom =  (mthbc(3).eq.2 .and. mthbc(4).eq.2)
      spheredom =  (mthbc(3).eq.5 .and. mthbc(4).eq.5)

      if ((mthbc(1).eq.2 .and. mthbc(2).ne.2) .or.
     &    (mthbc(2).eq.2 .and. mthbc(1).ne.2)) then
         write(6,*) '*** ERROR ***  periodic boundary conditions: '
         write(6,*) '  mthbc(1) and mthbc(2) must BOTH be set to 2'
         stop
         endif

      if ((mthbc(3).eq.2 .and. mthbc(4).ne.2) .or.
     &    (mthbc(4).eq.2 .and. mthbc(3).ne.2)) then
         write(6,*) '*** ERROR ***  periodic boundary conditions: '
         write(6,*) '  mthbc(3) and mthbc(4) must BOTH be set to 2'
         stop
         endif

      if ((mthbc(3).eq.5 .and. mthbc(4).ne.5) .or.
     &    (mthbc(4).eq.5 .and. mthbc(3).ne.5)) then
         write(6,*) '*** ERROR ***  sphere bcs at top and bottom: '
         write(6,*) '  mthbc(3) and mthbc(4) must BOTH be set to 5'
         stop
         endif

      if (spheredom .and. .not. xperdom) then
         write(6,*)'*** ERROR ***  sphere bcs at top and bottom: '
         write(6,*)'must go with periodic bcs at left and right  '
         stop
         endif


c     restart and checkpointing
c     -------------------------

      read(inunit,*) rest
      read(inunit,*) checkpt_style
      if (checkpt_style.eq.2) then
         read(inunit,*) nchkpt
         if (nchkpt .gt. maxout) then
            write(6,*) '*** Error nchkpt can be no greater than maxout'
            stop
            endif
         read(inunit,*) (tchk(i), i=1,nchkpt)
         endif
      if (checkpt_style.eq.3) then
         read(inunit,*) ichkpt
         endif

c
c     refinement variables
      read(inunit,*) flag_richardson
      read(inunit,*) tol            ! for richardson
      read(inunit,*) flag_gradient
      read(inunit,*) tolsp          ! for gradient
      read(inunit,*) kcheck
      read(inunit,*) ibuff
      read(inunit,*) cut
      read(inunit,*) verbosity_regrid
c
c     style of output
c
      read(inunit,*) output_format
      read(inunit,*) nq_components
      if (nq_components .gt. nvar) then
         write(6,*) '*** output_nq_components too large'
         stop
         endif
      read(inunit,*) (output_q_components(i),i=1,nq_components)
      read(inunit,*) naux_components
      if (naux_components .gt. naux) then
         write(6,*) '*** output_naux_components too large'
         stop
         endif
      read(inunit,*) (output_aux_components(i),i=1,naux_components)


c
c
c     # read verbose/debugging flags
      read(inunit,*) dprint
      read(inunit,*) eprint
      read(inunit,*) edebug
      read(inunit,*) gprint
      read(inunit,*) nprint
      read(inunit,*) pprint
      read(inunit,*) rprint
      read(inunit,*) sprint
      read(inunit,*) tprint
      read(inunit,*) uprint

      read(inunit,*) nregions
      if (nregions .gt. 0) then
         write(6,*) '*** Regions not yet implemented'
         stop
         endif

      call setgauges

      close(inunit)

c     # look for capacity function via auxtypes:
      mcapa = 0
      do 20 iaux = 1, naux
        if (auxtype(iaux) .eq. "capacity") then
          if (mcapa .ne. 0) then
            write(*,*)" only 1 capacity allowed"
            stop
          else
            mcapa = iaux
          endif
        endif

c       # change to Version 4.1 terminology:
        if (auxtype(iaux) .eq. "leftface") auxtype(iaux) = "xleft"
        if (auxtype(iaux) .eq. "bottomface") auxtype(iaux) = "yleft"

        if (.not. (auxtype(iaux) .eq."xleft" .or.
     .             auxtype(iaux) .eq. "yleft".or.
     .             auxtype(iaux) .eq. "capacity".or.
     .             auxtype(iaux) .eq. "center"))  then
                  write(*,*)" unknown type for auxiliary variables"
                  write(*,*)" use  xleft/yleft/center/capacity"
                  stop
        endif
   20   continue

c     ::: error checking of input data :::::::::::::::::::::::

      if (mcapa .ne. mcapa1) then
         write(outunit,*) 'Error ***  mcapa does not agree with auxtype'
         write(*,*) 'Error ***  mcapa does not agree with auxtype'
         stop
      endif
      if (nvar .gt. maxvar) then
         write(outunit,*) 'Error ***   nvar > maxvar in common'
         write(*,*)       'Error ***   nvar > maxvar in common'
         stop
      endif
      if (2*nghost .gt. min(nx,ny) .and. ny.ne.1) then
         mindim = 2*nghost
         write(outunit,*) 'Error ***   need finer domain >',
     .         mindim, ' cells'
         write(*,*)       'Error ***   need finer domain >',
     .         mindim, ' cells'
c        stop
      endif
      if (mcapa .gt. naux) then
         write(outunit,*) 'Error ***   mcapa > naux in input file'
         write(*,*)       'Error ***   mcapa > naux in input file'
         stop
      endif

      if (.not. vtime .and. nout .ne. 0) then
         write(outunit,*)' cannot specify output times with fixed dt'
         write(*,*)      ' cannot specify output times with fixed dt'
         stop
      endif
c
c
      if (ncarout)
     .   open(pltunit1,file=pltfile,status='unknown',form='formatted')
c
c
c     # write out parameters to fort.parameters if desired... (add?)
c
      write(parmunit,*) ' '
      write(parmunit,*) 'Running amrclaw with parameter values:'
      write(parmunit,*) ' '


      write(6,*) ' '
      write(6,*) 'Running amrclaw ...  '
      write(6,*) ' '

c     # default values of parameters that may be reset if user's setprob
c     # routine calls settopo, setdtopo, setqinit, setregions or setgauges.
      mgauges = 0
      mregions = 0

c     # call user routine to set up problem parameters:
      call setprob()

c
      matlabu   = 0
      hxposs(1) = (xupper - xlower) / nx
      hyposs(1) = (yupper - ylower) / ny
c
c
c
      if (rest) then
c        ### arg added to restrt for compatibility with geoclaw, which
c        ### allows variable refinement in time (and thus intrat vector
c        ### is allowed to change upon restart). In geoclaw the calling
c        ### sequence involves the variable varRefTime.
         open(outunit, file=outfile,status='unknown',access='append',
     .        form='formatted')
         call restrt(nsteps,time,nvar,.false.)
         nstart  = nsteps
         write(6,*) ' '
         write(6,*) 'Restarting from previous run'
         write(6,*) '   at time = ',time
         write(6,*) ' '
      else
         open(outunit, file=outfile,status='unknown',form='formatted')

         cflmax = 0.d0   ! otherwise use previously heckpointed val
         lentot = 0
         lenmax = 0
         lendim = 0
         rvol   = 0.0d0
         do i   = 1, mxnest
           rvoll(i) = 0.0d0
           enddo
         evol   = 0.0d0
         call   stst1


c	     # changed 4/24/09: store dxmin,dymin for setaux before
c    	 # grids are made, in order to average up from finest grid.
	     dxmin = hxposs(mxnest)
	     dymin = hyposs(mxnest)

         call   domain (nvar,vtime,nx,ny,naux,t0)

c        # Hold off on gauges until grids are set. 
c        # The fake call to advance at the very first timestep 
c        # looks at the gauge array but it is not yet built
         mgaugeSave = mgauges
         mgauges = 0
         call   setgrd (nvar,cut,naux,dtinit,t0)
         mgauges = mgaugeSave


         if (possk(1) .gt. dtinit*cflv1/cfl .and. vtime) then
c        ## initial time step was too large. reset to dt from setgrd
              write(6,*) "*** Initial time step reset for desired cfl"
              possk(1) = dtinit
              do i = 2, mxnest-1
                 possk(i) = possk(i-1)*kratio(i-1)
              end do
         endif

         time = t0
         nstart = 0
      endif


      write(parmunit,*) ' '
      write(parmunit,*) '--------------------------------------------'
      write(parmunit,*) ' '
      write(parmunit,*) '   rest = ', rest, '   (restart?)'
      write(parmunit,*) '   start time = ',time
      write(parmunit,*) ' '

!$    write(outunit,*)" max threads set to ",omp_get_max_threads()
!$    write(*,*)" max threads set to ",omp_get_max_threads()
c
c  print out program parameters for this run
c
      write(outunit,107)tol,tolsp,iorder,kcheck,ibuff,nghost,cut,
     1            mxnest,ichkpt,cfl
      write(outunit,109) xupper,yupper,xlower,ylower,nx,ny
      write(outunit,139)(intratx(i),i=1,mxnest)
      write(outunit,139)(intraty(i),i=1,mxnest)
      write(outunit,119) naux
      write(outunit,129) (iaux,auxtype(iaux),iaux=1,naux)
      if (mcapa .gt. 0) write(outunit,149) mcapa
107   format(/
     *       ' amrclaw parameters:',//,
     *       ' error tol            ',e12.5,/,
     *       ' spatial error tol    ',e12.5,/,
     *       ' order of integrator     ',i9,/,
     *       ' error checking interval ',i9,/,
     *       ' buffer zone size        ',i9,/,
     *       ' nghost                  ',i9,/,
     *       ' volume ratio cutoff  ',e12.5,/,
     *       ' max. refinement level   ',i9,/,
     *       ' user sub. calling times ',i9,/,
     *       ' cfl # (if var. delt) ',e12.5,/)
109   format(' xupper(upper corner) ',e12.5,/,
     *       ' yupper(upper corner) ',e12.5,/,
     *       ' xlower(lower corner) ',e12.5,/,
     *       ' ylower(lower corner) ',e12.5,/,
     *       ' nx = no. cells in x dir.',i9,/,
     *       ' ny = no. cells in y dir.',i9,/,
     *       ' refinement ratios       ',6i5,/,/)
119   format(' no. auxiliary vars.     ',i9)
129   format('       var ',i5,' of type ', a10)
139   format(' refinement ratios:       ',6i5,/)  
149   format(' capacity fn. is aux. var',i9)

      write(6,*) ' '
      write(6,*) 'Done reading data, starting computation ...  '
      write(6,*) ' '


      call outtre (mstart,printout,nvar,naux)
      write(outunit,*) "  original total mass ..."
      call conck(1,nvar,naux,time,rest)
      call valout(1,lfine,time,nvar,naux)
      close(parmunit)
c
c     --------------------------------------------------------
c     # tick is the main routine which drives the computation:
c     --------------------------------------------------------
      call tick(nvar,iout,nstart,nstop,cut,vtime,time,ichkpt,naux,
     &          nout,tout,tchk,time,rest,nchkpt)
c     --------------------------------------------------------

c     # Done with computation, cleanup:


      lentotsave = lentot
      call cleanup(nvar,naux)
      if (lentot .ne. 0) then
        write(outunit,*) lentot," words not accounted for ",
     &                   "in memory cleanup"
        write(*,*)        lentot," words not accounted for ",
     &                   "in memory cleanup"
      endif
c
c report on statistics
c
      open(matunit,file=matfile,status='unknown',form='formatted')
      write(matunit,*) matlabu-1
      write(matunit,*) mxnest
      close(matunit)

      write(outunit,*)
      write(outunit,*)
      write(outunit,901) lentotsave
      write(outunit,902) lenmax
      write(outunit,903) lendim

      write(outunit,904) rvol
      do 60 level = 1,mxnest
 60     write(outunit,905) level, rvoll(level)

      write(outunit,906) evol
      if (evol+rvol .gt. 0.) then
         ratmet = rvol / (evol+rvol) * 100.0d0
      else
         ratmet = 0.0d0
      endif
      write(outunit,907) ratmet
      write(outunit,908) cflmax

 901  format('current  space usage = ',i12)
 902  format('maximum  space usage = ',i12)
 903  format('need space dimension = ',i12,/)
 904  format('number of cells advanced for time integration = ',f20.6)
 905  format(3x,'# cells advanced on level ',i4,' = ',f20.2)
 906  format('number of cells advanced for error estimation = ',f20.6,/)
 907  format(' percentage of cells advanced in time  = ', f10.2)
 908  format(' maximum Courant number seen = ', f10.2)
c
      write(outunit,909)
 909  format(//,' ------  end of AMRCLAW integration --------  ')
c
c     # Close output and debug files.
      close(outunit)
      close(dbugunit)
c
      stop
      end program amr2
