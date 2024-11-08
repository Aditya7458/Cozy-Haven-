-- Create Database
CREATE DATABASE CozyHavenStays;
GO

USE CozyHavenStays;
GO

-- Create Users Table
CREATE TABLE Users (
    UserId NVARCHAR(50) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) UNIQUE NOT NULL,
    Password NVARCHAR(255) NOT NULL,
    Phone NVARCHAR(20) NOT NULL,
    Gender NVARCHAR(10),
    Address NVARCHAR(255),
    Role NVARCHAR(20) DEFAULT 'USER' CHECK (Role IN ('USER', 'HOTEL_OWNER', 'ADMIN')),
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE()
);

-- Create Locations Table
CREATE TABLE Locations (
    LocationId NVARCHAR(50) PRIMARY KEY,
    City NVARCHAR(100) NOT NULL,
    Country NVARCHAR(100) NOT NULL,
    Address NVARCHAR(255) NOT NULL,
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE()
);

-- Create Hotels Table
CREATE TABLE Hotels (
    HotelId NVARCHAR(50) PRIMARY KEY,
    LocationId NVARCHAR(50) FOREIGN KEY REFERENCES Locations(LocationId),
    Name NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX),
    HasParking BIT DEFAULT 0,
    HasDining BIT DEFAULT 0,
    HasWifi BIT DEFAULT 0,
    HasRoomService BIT DEFAULT 0,
    HasPool BIT DEFAULT 0,
    HasFitnessCenter BIT DEFAULT 0,
    Rating DECIMAL(3,2),
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE()
);

-- Create Rooms Table
CREATE TABLE Rooms (
    RoomId NVARCHAR(50) PRIMARY KEY,
    HotelId NVARCHAR(50) FOREIGN KEY REFERENCES Hotels(HotelId),
    RoomSize NVARCHAR(50) NOT NULL, -- e.g., '70 m²/753 ft²'
    BedType NVARCHAR(20) CHECK (BedType IN ('SINGLE', 'DOUBLE', 'KING')) NOT NULL,
    MaxOccupancy INT NOT NULL,
    BaseFare DECIMAL(10,2) NOT NULL,
    IsAC BIT DEFAULT 1,
    Status NVARCHAR(20) DEFAULT 'AVAILABLE' CHECK (Status IN ('AVAILABLE', 'BOOKED', 'MAINTENANCE')),
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE()
);

-- Create Bookings Table
CREATE TABLE Bookings (
    BookingId NVARCHAR(50) PRIMARY KEY,
    UserId NVARCHAR(50) FOREIGN KEY REFERENCES Users(UserId),
    RoomId NVARCHAR(50) FOREIGN KEY REFERENCES Rooms(RoomId),
    CheckInDate DATE NOT NULL,
    CheckOutDate DATE NOT NULL,
    NumAdults INT NOT NULL,
    NumChildren INT DEFAULT 0,
    TotalAmount DECIMAL(10,2) NOT NULL,
    Status NVARCHAR(20) DEFAULT 'PENDING' CHECK (Status IN ('PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED')),
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE(),
    CONSTRAINT CHK_Dates CHECK (CheckOutDate > CheckInDate)
);

-- Create Payments Table
CREATE TABLE Payments (
    PaymentId NVARCHAR(50) PRIMARY KEY,
    BookingId NVARCHAR(50) FOREIGN KEY REFERENCES Bookings(BookingId),
    Amount DECIMAL(10,2) NOT NULL,
    PaymentMethod NVARCHAR(50) NOT NULL,
    PaymentDate DATETIME NOT NULL,
    Status NVARCHAR(20) DEFAULT 'PENDING' CHECK (Status IN ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED')),
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE()
);

-- Create Cancellations Table
CREATE TABLE Cancellations (
    CancellationId NVARCHAR(50) PRIMARY KEY,
    BookingId NVARCHAR(50) FOREIGN KEY REFERENCES Bookings(BookingId),
    CancellationDate DATETIME NOT NULL,
    RefundAmount DECIMAL(10,2) NOT NULL,
    Status NVARCHAR(20) DEFAULT 'PENDING' CHECK (Status IN ('PENDING', 'PROCESSED', 'REJECTED')),
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE()
);

-- Create Reviews Table
CREATE TABLE Reviews (
    ReviewId NVARCHAR(50) PRIMARY KEY,
    UserId NVARCHAR(50) FOREIGN KEY REFERENCES Users(UserId),
    RoomId NVARCHAR(50) FOREIGN KEY REFERENCES Rooms(RoomId),
    Rating INT CHECK (Rating BETWEEN 1 AND 5) NOT NULL,
    Comment NVARCHAR(MAX),
    ReviewDate DATETIME DEFAULT GETDATE(),
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME DEFAULT GETDATE()
);

-- Create stored procedure for calculating room price based on occupancy
CREATE PROCEDURE CalculateRoomPrice
    @RoomId NVARCHAR(50),
    @NumAdults INT,
    @NumChildren INT,
    @TotalPrice DECIMAL(10,2) OUTPUT
AS
BEGIN
    DECLARE @BaseFare DECIMAL(10,2)
    DECLARE @BedType NVARCHAR(20)
    DECLARE @MaxOccupancy INT
    DECLARE @AdditionalCharge DECIMAL(10,2) = 0

    -- Get room details
    SELECT @BaseFare = BaseFare, @BedType = BedType, @MaxOccupancy = MaxOccupancy
    FROM Rooms
    WHERE RoomId = @RoomId

    -- Initialize total price with base fare
    SET @TotalPrice = @BaseFare

    -- Calculate additional charges based on bed type and occupancy
    IF @BedType = 'SINGLE' AND (@NumAdults + @NumChildren) > 1
    BEGIN
        -- Additional 40% for adults, 20% for children beyond first person
        SET @AdditionalCharge = @BaseFare * 0.4 * (@NumAdults - 1) +
                               @BaseFare * 0.2 * @NumChildren
    END
    ELSE IF @BedType = 'DOUBLE' AND (@NumAdults + @NumChildren) > 2
    BEGIN
        -- Additional 40% for adults, 20% for children beyond second person
        SET @AdditionalCharge = @BaseFare * 0.4 * (@NumAdults - 2) +
                               @BaseFare * 0.2 * @NumChildren
    END
    ELSE IF @BedType = 'KING' AND (@NumAdults + @NumChildren) > 4
    BEGIN
        -- Additional 40% for adults, 20% for children beyond fourth person
        SET @AdditionalCharge = @BaseFare * 0.4 * (@NumAdults - 4) +
                               @BaseFare * 0.2 * @NumChildren
    END

    -- Add additional charge to total price
    SET @TotalPrice = @TotalPrice + @AdditionalCharge
END;

-- Create trigger to update hotel rating when new review is added
CREATE TRIGGER UpdateHotelRating
ON Reviews
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    DECLARE @HotelId NVARCHAR(50)

    -- Get affected hotel ID from inserted or deleted reviews
    SELECT DISTINCT @HotelId = h.HotelId
    FROM Hotels h
    JOIN Rooms r ON h.HotelId = r.HotelId
    JOIN (
        SELECT RoomId FROM inserted
        UNION
        SELECT RoomId FROM deleted
    ) affected ON r.RoomId = affected.RoomId

    -- Update hotel rating
    UPDATE Hotels
    SET Rating = (
        SELECT AVG(CAST(r.Rating AS DECIMAL(3,2)))
        FROM Reviews r
        JOIN Rooms rm ON r.RoomId = rm.RoomId
        WHERE rm.HotelId = @HotelId
    )
    WHERE HotelId = @HotelId
END;

-- Insert sample data
INSERT INTO Users (UserId, Name, Email, Password, Phone, Role)
VALUES 
('U1', 'John Doe', 'john@example.com', 'hashedpassword123', '1234567890', 'USER'),
('U2', 'Admin User', 'admin@cozyhaven.com', 'hashedpassword456', '9876543210', 'ADMIN'),
('U3', 'Hotel Owner', 'owner@hotel.com', 'hashedpassword789', '5555555555', 'HOTEL_OWNER');

INSERT INTO Locations (LocationId, City, Country, Address)
VALUES 
('L1', 'New York', 'USA', '123 Broadway St'),
('L2', 'London', 'UK', '456 Oxford St');

INSERT INTO Hotels (HotelId, LocationId, Name, Description, HasWifi, HasParking)
VALUES 
('H1', 'L1', 'Cozy Manhattan', 'Luxury hotel in downtown Manhattan', 1, 1),
('H2', 'L2', 'London Comfort', 'Elegant stay in central London', 1, 1);

INSERT INTO Rooms (RoomId, HotelId, RoomSize, BedType, MaxOccupancy, BaseFare, IsAC)
VALUES 
('R1', 'H1', '70 m²/753 ft²', 'KING', 6, 200.00, 1),
('R2', 'H1', '40 m²/430 ft²', 'DOUBLE', 4, 150.00, 1),
('R3', 'H2', '35 m²/376 ft²', 'SINGLE', 2, 100.00, 1);
