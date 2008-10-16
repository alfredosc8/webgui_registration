-- MySQL dump 10.11
--
-- Host: localhost    Database: dev_head
-- ------------------------------------------------------
-- Server version	5.0.45

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `Registration`
--

DROP TABLE IF EXISTS `Registration`;
CREATE TABLE `Registration` (
  `registrationId` varchar(22) NOT NULL,
  `title` varchar(255) default NULL,
  `url` varchar(255) default NULL,
  `stepTemplateId` varchar(22) default NULL,
  `styleTemplateId` varchar(22) default NULL,
  `confirmationTemplateId` varchar(22) default NULL,
  `registrationCompleteTemplateId` varchar(22) default NULL,
  `noValidUserTemplateId` varchar(22) default NULL,
  `setupCompleteMailTemplateId` varchar(22) default NULL,
  `setupCompleteMailSubject` varchar(255) default NULL,
  `siteApprovalMailTemplateId` varchar(22) default NULL,
  `siteApprovalMailSubject` varchar(255) default NULL,
  `removeAccountWorkflowId` varchar(22) default NULL,
  PRIMARY KEY  (`registrationId`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Table structure for table `RegistrationStep`
--

DROP TABLE IF EXISTS `RegistrationStep`;
CREATE TABLE `RegistrationStep` (
  `stepId` varchar(22) NOT NULL,
  `registrationId` varchar(22) NOT NULL,
  `stepOrder` int(3) default NULL,
  `options` text,
  `namespace` varchar(255) default NULL,
  PRIMARY KEY  (`stepId`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Table structure for table `RegistrationStep_accountData`
--

DROP TABLE IF EXISTS `RegistrationStep_accountData`;
CREATE TABLE `RegistrationStep_accountData` (
  `stepId` varchar(22) NOT NULL,
  `userId` varchar(22) NOT NULL,
  `status` varchar(20) default NULL,
  `configurationData` text,
  PRIMARY KEY  (`stepId`,`userId`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Table structure for table `Registration_status`
--

DROP TABLE IF EXISTS `Registration_status`;
CREATE TABLE `Registration_status` (
  `registrationId` varchar(22) NOT NULL,
  `userId` varchar(22) NOT NULL,
  `status` varchar(20) NOT NULL default 'setup',
  PRIMARY KEY  (`registrationId`,`userId`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2008-10-16  8:55:36
