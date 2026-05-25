module mylib
   use iso_c_binding
   use, intrinsic :: ieee_arithmetic
   implicit none
   integer, parameter :: cols = 3840
contains

   subroutine makeRow(rehi, imhi, relo, imlo, stephi, steplo, speclen, maxitr, blout, clout) bind(C, name="makeRow")
      implicit none
      real(c_double), value :: rehi, imhi, relo, imlo, stephi, steplo
      integer(c_int8_t), intent(out) :: blout(cols), clout(cols)
      integer(c_int), value :: speclen, maxitr
      integer(c_int) :: colgroup
      real(c_double) :: idxctr(4) ! counts through with start of 0123 and each time +4 to move on to next group
      real(c_double) :: orehi(4)
      real(c_double) :: oimhi(4)
      real(c_double) :: orelo(4)
      real(c_double) :: oimlo(4)
      real(c_double) :: crehi(4) ! will also store squares
      real(c_double) :: cimhi(4)
      real(c_double) :: crelo(4)
      real(c_double) :: cimlo(4)
      real(c_double) :: imrehi(4) ! stores the re*im so re and im can safety in place square to conserve registers
      real(c_double) :: imrelo(4)
      real(c_double) :: tsrehi(4), tsrelo(4)
      real(c_double) :: tsstephi(4), tssteplo(4)
      real(c_double) :: mag(4) ! a minor inaccuracy doesnt matter below 1e-15 or border no one cares but i might regret it later
      integer(c_int) :: itr
      logical :: ctnue(4)
      integer(c_int) :: res(4)
      ! cannot vectorize the following loop
      idxctr = [0, 1, 2, 3]
      oimhi = imhi
      oimlo = imlo
      tsrehi = rehi
      tsrelo = relo
      tsstephi = stephi
      tssteplo = steplo
      do colgroup = 1, cols, 4
         ! do mandelbrot
         ! Step 1: load into array

         res = [0, 0, 0, 0]
         call double2c(tsstephi, tssteplo, idxctr, orehi, orelo) !idxctr*step
         call double2add(orehi, orelo, tsrehi, tsrelo, orehi, orelo) !+=re (I can verify my functions can do in place)

         ! Step 2: prep cre,cim

         crehi = orehi
         cimhi = oimhi
         crelo = orelo
         cimlo = oimlo

         ! Step 3: Run Mandelbrot iteration

         do itr = 1, maxitr
            ! Step 3-1: find 2re*im
            call double2mul(crehi, crelo, cimhi, cimlo, imrehi, imrelo) ! multiply
            call double2add(imrehi, imrelo, imrehi, imrelo, imrehi, imrelo) ! double it
            ! Step 3-2: square re and im in place
            call double2mul(crehi, crelo, crehi, crelo, crehi, crelo)
            call double2mul(cimhi, cimlo, cimhi, cimlo, cimhi, cimlo)
            ! Step 3-3: find magnitude
            mag = crehi + cimhi
            ! Step 3-4: update res and break if needed
            ctnue = mag < 4
            if (.not. any(ctnue)) then
               exit
            end if
            res = res + merge(1, 0, ctnue) ! gfortran lets me implicit but hopefully i dont get bit in the back
            ! Step 3-5: update re and im
            call double2sub(crehi, crelo, cimhi, cimlo, crehi, crelo)
            call double2add(crehi, crelo, orehi, orelo, crehi, crelo) ! re^2-im^2+ore
            call double2add(imrehi, imrelo, oimhi, oimlo, cimhi, cimlo)
         end do

         ! Step 4: increment the idxctr
         idxctr = idxctr + 4
         ! Step 5: output
         blout(colgroup:colgroup + 3) = int(merge(0, 255, res == maxitr), kind=c_int8_t)!transfer(merge(0, 255, res == maxitr), blout)
         res = (res*256)/speclen ! multiply first makes it so it doesnt lose too much and this should scale
         clout(colgroup:colgroup + 3) = int(iand(res, 255), kind=c_int8_t)!transfer(res, clout) ! relying on gfortran truncation (hopefully doesnt bite me in the back)
      end do
   end subroutine makeRow

   pure subroutine double2add(ahi, alo, bhi, blo, chi, clo) ! does 4 at a time because avx2
      implicit none
      real(c_double), intent(in), dimension(4) :: ahi, alo, bhi, blo
      real(c_double), intent(out), dimension(4) :: chi, clo
      ! TwoSum(ahi,bhi)
      real(c_double), dimension(4) :: sum, err, v
      sum = ahi + bhi
      v = sum - ahi
      err = (ahi - (sum - v)) + (bhi - v)
      ! e += a_lo + b_lo
      err = err + alo
      err = err + blo
      ! (s, e) = TwoSum(s, e) (twosum needed as ahi and bhi may have opposite signs bringing it down below)
      chi = sum + err
      v = chi - sum
      clo = (sum - (chi - v)) + (err - v)
   end subroutine double2add

   pure subroutine double2sub(ahi, alo, bhi, blo, chi, clo) ! does 4 at a time because avx2
      implicit none
      real(c_double), intent(in), dimension(4) :: ahi, alo, bhi, blo
      real(c_double), intent(out), dimension(4) :: chi, clo
      ! TwoSum(ahi,-bhi)
      real(c_double), dimension(4) :: sum, err, v
      sum = ahi - bhi
      v = sum - ahi
      err = (ahi - (sum - v)) + (-bhi - v)
      ! e += a_lo - b_lo
      err = err + alo
      err = err - blo
      ! (s, e) = TwoSum(s, e) (twosum needed as ahi and bhi may have opposite signs bringing it down below)
      chi = sum + err
      v = chi - sum
      clo = (sum - (chi - v)) + (err - v)
   end subroutine double2sub

   ! pure function fma(a, b, c)
   !    implicit none
   !    ! real(c_double), intent(inout), dimension(4) :: a
   !    ! real(c_double), intent(in), dimension(4) :: b, c
   !    ! integer :: i
   !    ! ! vectorize loop
   !    ! !GCC$ VECTOR
   !    ! do i = 1, 4
   !    !    a(i) = ieee_fma(b(i), c(i), a(i))
   !    ! end do
   !    real(c_double), intent(in) :: a, b, c
   ! end subroutine fma

   pure subroutine double2mul(ahi, alo, bhi, blo, chi, clo) ! does 4 at a time because avx2
      implicit none
      real(c_double), intent(in), dimension(4) :: ahi, alo, bhi, blo
      real(c_double), intent(out), dimension(4) :: chi, clo
      ! slughtly simplified so 1 less bit but whatever i wont track errors below because it can change stuff by at most like 1 which isnt a huge deal
      ! find ahi*bhi with error
      real(c_double), dimension(4) :: p, err, v
      p = ahi*bhi
      !print *, "Err before", err
      !call fma(err, ahi, bhi) ! find error (ahi*bhi-p)
      err = ieee_fma(ahi, bhi, -p)
      !print *, "Err after", err
      err = ieee_fma(alo, bhi, err)
      err = ieee_fma(ahi, blo, err)
      ! call fma(err, alo, bhi)
      ! call fma(err, ahi, blo)
      ! print *, "Err after2", err
      ! alo*blo not worth it
      chi = p + err
      v = chi - p
      clo = (p - (chi - v)) + (err - v)
   end subroutine double2mul
   pure subroutine double2c(ahi, alo, b, chi, clo) ! does 4 at a time because avx2
      implicit none
      real(c_double), intent(in), dimension(4) :: ahi, alo, b
      real(c_double), intent(out), dimension(4) :: chi, clo
      ! slughtly simplified so 1 less bit but whatever i wont track errors below because it can change stuff by at most like 1 which isnt a huge deal
      ! find ahi*bhi with error
      real(c_double), dimension(4) :: p, err, v
      p = ahi*b
      !print *, "Err before", err
      !call fma(err, ahi, bhi) ! find error (ahi*bhi-p)
      err = ieee_fma(ahi, b, -p)
      !print *, "Err after", err
      err = ieee_fma(alo, b, err)
      ! call fma(err, alo, bhi)
      ! call fma(err, ahi, blo)
      ! print *, "Err after2", err
      ! alo*blo not worth it
      chi = p + err
      v = chi - p
      clo = (p - (chi - v)) + (err - v)
   end subroutine double2c
end module mylib
